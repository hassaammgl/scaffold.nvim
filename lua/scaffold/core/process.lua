-- Process execution helpers.
--
-- Rules enforced here:
--   * argv arrays only, never shell strings
--   * every argument validated before it is handed to vim.system/termopen
--   * long-running commands run in native terminal buffers
--   * running jobs are tracked so the user can cancel them

local validator = require("scaffold.core.validator")
local fs = require("scaffold.core.filesystem")
local events = require("scaffold.core.events")
local utils = require("scaffold.utils")

local M = {}

M.jobs = {}
M.system_jobs = {}

function M.executable(name)
  if type(name) ~= "string" or name == "" or name:find("%z") then
    return false
  end
  return vim.fn.executable(name) == 1
end

function M.which(name)
  if not M.executable(name) then
    return nil
  end
  local path = vim.fn.exepath(name)
  if path == "" then
    return nil
  end
  return path
end

-- vim.system/jobstart treat env tables as a complete environment on some
-- Neovim versions, so always merge with the current environment.
local function merged_env(env)
  if not env then
    return nil
  end
  local result = vim.fn.environ()
  for key, value in pairs(env) do
    result[key] = tostring(value)
  end
  return result
end

-- Synchronous execution with a hard timeout. Returns vim.system's result
-- table ({ code, signal, stdout, stderr }) or nil, error.
function M.run_sync(argv, opts)
  opts = opts or {}
  local ok, err = validator.command(argv)
  if not ok then
    return nil, err
  end
  if opts.cwd ~= nil and not fs.is_dir(opts.cwd) then
    return nil, "working directory does not exist: " .. tostring(opts.cwd)
  end

  local request = {
    cwd = opts.cwd,
    env = merged_env(opts.env),
    text = true,
    timeout = opts.timeout or 5000,
    stdin = "null",
  }

  local called, system = pcall(vim.system, argv, request)
  if not called then
    return nil, tostring(system)
  end
  local waited, result = pcall(function()
    return system:wait()
  end)
  if not waited then
    return nil, tostring(result)
  end
  return result
end

-- Convenience wrapper returning code, stdout, stderr.
function M.capture(argv, opts)
  local result, err = M.run_sync(argv, opts)
  if not result then
    return nil, "", err
  end
  return result.code, result.stdout or "", result.stderr or ""
end

--- Close an output window if it is still around. Finished jobs also lose their
--- buffer so repeated builds do not leave `scaffold://` buffers behind; a job
--- that is still running keeps its (hidden) buffer so :ScaffoldCancel can reach
--- it.
---@param win integer?
---@param buf integer?
function M.close_window(win, buf)
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if vim.bo[buf].buftype ~= "terminal" then
    return
  end
  for _, job in pairs(M.jobs) do
    if job.buf == buf then
      return
    end
  end
  vim.bo[buf].bufhidden = "wipe"
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
end

--- q / <Esc> close the output window (a running job keeps going, its buffer is
--- hidden, so `:ScaffoldCancel` can still reach it).
---@param buf integer
---@param win integer
function M.bind_close(buf, win)
  local function close()
    M.close_window(win, buf)
  end
  for _, lhs in ipairs({ "q", "<Esc>" }) do
    pcall(vim.keymap.set, "n", lhs, close, { buffer = buf, nowait = true, desc = "Scaffold: close output window" })
  end
  -- in terminal mode only <Esc> is taken over, `q` must still reach the program
  pcall(vim.keymap.set, "t", "<Esc>", close, { buffer = buf, nowait = true, desc = "Scaffold: close output window" })
end

--- Open the window that will show command output.
--- `command_window = "float"` (default) uses a centered float; `"split"` opens
--- a separate split (`terminal_split`). Either way a brand new scratch buffer is
--- created and put into the new window, so the buffer you were editing is never
--- replaced (this used to `:split` and `termopen` in the current buffer, which
--- turned the open file into a terminal).
---@param title string
---@param opts? {mode?: string, split?: string}
---@return integer buf
---@return integer win
---@return string mode
function M.command_window(title, opts)
  opts = opts or {}
  local config = require("scaffold.config")
  local mode = opts.mode or config.get("command_window") or "float"
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].swapfile = false

  if mode ~= "split" then
    local float = config.get("float") or {}
    local width = math.max(20, math.min(vim.o.columns - 2, math.floor(vim.o.columns * (float.width or 0.8))))
    local height = math.max(6, math.min(vim.o.lines - 2, math.floor(vim.o.lines * (float.height or 0.5))))
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
      col = math.max(0, math.floor((vim.o.columns - width) / 2)),
      style = "minimal",
      border = float.border or "rounded",
      title = " " .. tostring(title) .. " ",
      title_pos = "center",
    })
    vim.wo[win].wrap = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].foldcolumn = "0"
    return buf, win, "float"
  end

  local previous = vim.api.nvim_get_current_win()
  local split = opts.split
  if split == nil then
    split = config.get("terminal_split")
  end
  if split and split ~= "" then
    pcall(vim.cmd, split)
  end
  local win = vim.api.nvim_get_current_win()
  if win == previous then
    vim.cmd("botright split")
    win = vim.api.nvim_get_current_win()
  end
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].wrap = false
  return buf, win, "split"
end

function M.terminal(argv, opts)
  opts = opts or {}
  local ok, err = validator.command(argv)
  if not ok then
    return nil, err
  end
  if opts.cwd ~= nil and not fs.is_dir(opts.cwd) then
    return nil, "working directory does not exist: " .. tostring(opts.cwd)
  end

  local label = opts.label or "command"
  local buffer, win, mode = M.command_window(label, opts)
  local buf = buffer
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "scaffold-terminal"
  local job_id = vim.fn.termopen(argv, {
    cwd = opts.cwd,
    env = merged_env(opts.env),
    on_exit = function(id, code)
      vim.schedule(function()
        M.jobs[id] = nil
        if require("scaffold.config").get("notify_on_exit") then
          local level = code == 0 and vim.log.levels.INFO or vim.log.levels.WARN
          utils.notify(
            ("Scaffold %s: %s (exit %s)"):format(label, code == 0 and "finished" or "exited", tostring(code)),
            level
          )
        end
        events.emit("job_exited", {
          id = id,
          code = code,
          argv = vim.deepcopy(argv),
          cwd = opts.cwd,
          label = label,
          type = "terminal",
        })
        -- window already closed while it ran: do not leave the buffer behind
        local displayed = false
        for _, other in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_buf(other) == buf then
            displayed = true
            break
          end
        end
        if not displayed and vim.api.nvim_buf_is_valid(buf) then
          vim.bo[buf].bufhidden = "wipe"
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end)
    end,
  })

  if job_id <= 0 then
    M.close_window(win)
    return nil, "failed to start process: " .. utils.display_argv(argv)
  end

  local safe_label = label:gsub("[^%w_-]+", "-")
  pcall(vim.api.nvim_buf_set_name, buf, ("scaffold://%s/%d"):format(safe_label, job_id))

  M.bind_close(buf, win)

  M.jobs[job_id] = {
    id = job_id,
    buf = buf,
    argv = vim.deepcopy(argv),
    cwd = opts.cwd,
    label = label,
    started_at = os.time(),
  }

  events.emit("job_started", {
    id = job_id,
    argv = vim.deepcopy(argv),
    cwd = opts.cwd,
    label = label,
    type = "terminal",
  })

  return job_id, buf
end

local function append_lines(appends, lines)
  if #lines == 0 then
    return
  end
  vim.schedule(function()
    for _, entry in ipairs(appends) do
      local buf = entry.buf
      if vim.api.nvim_buf_is_valid(buf) then
        vim.bo[buf].modifiable = true
        local start = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_buf_set_lines(buf, start, start, false, lines)
        if entry.follow and vim.api.nvim_get_current_buf() == buf then
          pcall(vim.api.nvim_win_set_cursor, 0, { vim.api.nvim_buf_line_count(buf), 0 })
        end
        vim.bo[buf].modifiable = false
      end
    end
  end)
end

-- Create a window used to display captured output (never the buffer you are
-- editing: it always gets a fresh scratch buffer).
function M.open_output(title, opts)
  opts = opts or {}
  local buf, win = M.command_window(title or "Scaffold output", opts)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "scaffold-output"
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "Scaffold.nvim — " .. (title or "output"),
  })
  vim.bo[buf].modifiable = false
  M.bind_close(buf, win)
  return buf
end

-- Run a process asynchronously and stream its output into a buffer.
-- Returns pid, buf or nil, error.
function M.captured(argv, opts, on_exit)
  opts = opts or {}
  local ok, err = validator.command(argv)
  if not ok then
    return nil, err
  end
  if opts.cwd ~= nil and not fs.is_dir(opts.cwd) then
    return nil, "working directory does not exist: " .. tostring(opts.cwd)
  end

  local buf = opts.buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    buf = M.open_output(opts.label or "output", opts)
  end

  local appends = { { buf = buf, follow = opts.follow ~= false } }
  append_lines(appends, {
    "",
    "$ " .. utils.display_argv(argv),
    "cwd: " .. tostring(opts.cwd or vim.uv.cwd()),
    "",
  })

  local stdout_handler = function(_, data)
    if data and data ~= "" then
      local lines = vim.split(data, "\n", { plain = true })
      append_lines(appends, lines)
    end
  end
  local stderr_handler = function(_, data)
    if data and data ~= "" then
      local lines = vim.split(data, "\n", { plain = true })
      append_lines(appends, lines)
    end
  end

  local called, system = pcall(vim.system, argv, {
    cwd = opts.cwd,
    env = merged_env(opts.env),
    text = true,
    stdin = opts.stdin or "null",
    stdout = stdout_handler,
    stderr = stderr_handler,
  }, function(result)
    vim.schedule(function()
      if system and system.pid then
        M.system_jobs[system.pid] = nil
      end
      local code = result and result.code
      append_lines(appends, {
        "",
        ("[exit %s]"):format(tostring(code)),
        "",
      })
      if require("scaffold.config").get("notify_on_exit") then
        local level = code == 0 and vim.log.levels.INFO or vim.log.levels.WARN
        utils.notify(
          ("Scaffold %s: %s (exit %s)"):format(opts.label or "task", code == 0 and "finished" or "failed", tostring(code)),
          level
        )
      end
      events.emit("job_exited", {
        id = system and system.pid,
        code = code,
        argv = vim.deepcopy(argv),
        cwd = opts.cwd,
        label = opts.label or "task",
        type = "system",
      })
      if on_exit then
        local handler_ok, handler_err = pcall(on_exit, result)
        if not handler_ok then
          utils.warn("Scaffold output handler failed: " .. tostring(handler_err))
        end
      end
    end)
  end)

  if not called or not system then
    return nil, tostring(system)
  end

  M.system_jobs[system.pid] = {
    id = system.pid,
    type = "system",
    buf = buf,
    argv = vim.deepcopy(argv),
    cwd = opts.cwd,
    label = opts.label or "task",
    object = system,
    started_at = os.time(),
  }

  events.emit("job_started", {
    id = system.pid,
    argv = vim.deepcopy(argv),
    cwd = opts.cwd,
    label = opts.label or "task",
    type = "system",
  })

  return system.pid, buf
end

function M.cancel(job_id)
  if type(job_id) ~= "number" then
    return false, "unknown job"
  end
  if M.jobs[job_id] then
    local ok, err = pcall(vim.fn.jobstop, job_id)
    if not ok then
      return false, tostring(err)
    end
    M.jobs[job_id] = nil
    return true
  end
  local job = M.system_jobs[job_id]
  if job then
    local ok, err = pcall(function()
      job.object:kill(15)
    end)
    if not ok then
      return false, tostring(err)
    end
    M.system_jobs[job_id] = nil
    return true
  end
  return false, "unknown job"
end

function M.cancel_all()
  local count = 0
  local ids = {}
  for job_id in pairs(M.jobs) do
    ids[#ids + 1] = job_id
  end
  for job_id in pairs(M.system_jobs) do
    ids[#ids + 1] = job_id
  end
  for _, job_id in ipairs(ids) do
    if M.cancel(job_id) then
      count = count + 1
    end
  end
  return count
end

function M.list_jobs()
  local jobs = {}
  for _, job in pairs(M.jobs) do
    jobs[#jobs + 1] = job
  end
  for _, job in pairs(M.system_jobs) do
    jobs[#jobs + 1] = job
  end
  table.sort(jobs, function(a, b)
    return a.id < b.id
  end)
  return jobs
end

return M
