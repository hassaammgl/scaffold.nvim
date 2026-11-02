-- Process execution helpers.
--
-- Rules enforced here:
--   * argv arrays only, never shell strings
--   * every argument validated before it is handed to vim.system/termopen
--   * long-running commands run in native terminal buffers
--   * running jobs are tracked so the user can cancel them

local validator = require("forge.core.validator")
local fs = require("forge.core.filesystem")
local utils = require("forge.utils")

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

function M.terminal(argv, opts)
  opts = opts or {}
  local ok, err = validator.command(argv)
  if not ok then
    return nil, err
  end
  if opts.cwd ~= nil and not fs.is_dir(opts.cwd) then
    return nil, "working directory does not exist: " .. tostring(opts.cwd)
  end

  local previous_win = vim.api.nvim_get_current_win()
  local split = opts.split
  if split == nil then
    split = require("forge.config").get("terminal_split")
  end

  if split and split ~= "" then
    local opened = pcall(vim.cmd, split)
    if not opened then
      return nil, "could not open terminal split: " .. split
    end
  end

  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "forge-terminal"

  local label = opts.label or "command"
  local job_id = vim.fn.termopen(argv, {
    cwd = opts.cwd,
    env = merged_env(opts.env),
    on_exit = function(id, code)
      vim.schedule(function()
        M.jobs[id] = nil
        if require("forge.config").get("notify_on_exit") then
          local level = code == 0 and vim.log.levels.INFO or vim.log.levels.WARN
          utils.notify(
            ("Forge %s: %s (exit %s)"):format(label, code == 0 and "finished" or "exited", tostring(code)),
            level
          )
        end
      end)
    end,
  })

  if job_id <= 0 then
    if split and split ~= "" then
      pcall(vim.cmd, "close")
      pcall(vim.api.nvim_set_current_win, previous_win)
    end
    return nil, "failed to start process: " .. utils.display_argv(argv)
  end

  local safe_label = label:gsub("[^%w_-]+", "-")
  pcall(vim.api.nvim_buf_set_name, buf, ("forge://%s/%d"):format(safe_label, job_id))

  M.jobs[job_id] = {
    id = job_id,
    buf = buf,
    argv = vim.deepcopy(argv),
    cwd = opts.cwd,
    label = label,
    started_at = os.time(),
  }

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

-- Create a split buffer used to display captured output.
function M.open_output(title, opts)
  opts = opts or {}
  local split = opts.split
  if split == nil then
    split = require("forge.config").get("terminal_split")
  end
  if split and split ~= "" then
    pcall(vim.cmd, split)
  end
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "forge-output"
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "Forge.nvim — " .. (title or "output"),
  })
  vim.bo[buf].modifiable = false
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
      if require("forge.config").get("notify_on_exit") then
        local level = code == 0 and vim.log.levels.INFO or vim.log.levels.WARN
        utils.notify(
          ("Forge %s: %s (exit %s)"):format(opts.label or "task", code == 0 and "finished" or "failed", tostring(code)),
          level
        )
      end
      if on_exit then
        local handler_ok, handler_err = pcall(on_exit, result)
        if not handler_ok then
          utils.warn("Forge output handler failed: " .. tostring(handler_err))
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
