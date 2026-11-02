-- Floating windows built with nvim_open_win.
-- Highlights link to existing editor groups by default so themes are respected.

local utils = require("scaffold.utils")

local M = {}

M.ns = vim.api.nvim_create_namespace("scaffold.ui")

M.highlights = {
  ScaffoldTitle = "Title",
  ScaffoldSection = "Title",
  ScaffoldKey = "Identifier",
  ScaffoldMuted = "Comment",
  ScaffoldOk = "DiagnosticOk",
  ScaffoldWarn = "DiagnosticWarn",
  ScaffoldError = "DiagnosticError",
  ScaffoldAccent = "Special",
}

function M.ensure_highlights()
  for group, link in pairs(M.highlights) do
    pcall(vim.api.nvim_set_hl, 0, group, { link = link, default = true })
  end
end

function M.ui_available()
  local ok, uis = pcall(vim.api.nvim_list_uis)
  return ok and uis and #uis > 0
end

-- opts:
--   lines, title, width, height, filetype, highlights, keymaps,
--   cursorline, close_key, on_close, footer
function M.open(opts)
  opts = opts or {}
  if not M.ui_available() then
    return nil, "no UI attached"
  end
  M.ensure_highlights()

  local lines = vim.deepcopy(opts.lines or {})
  if #lines == 0 then
    lines = { "" }
  end

  local total_width = vim.o.columns
  local total_height = vim.o.lines - vim.o.cmdheight
  local width = opts.width or math.min(96, math.max(40, total_width - 8))
  width = math.max(20, math.min(width, total_width - 2))
  local height = opts.height or math.min(#lines, total_height - 6)
  height = math.max(1, math.min(height, math.max(1, total_height - 4)))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = opts.filetype or "scaffold"

  local win_opts = {
    relative = "editor",
    style = "minimal",
    border = opts.border or "rounded",
    width = width,
    height = height,
    row = math.max(1, math.floor((total_height - height) / 2) - 1),
    col = math.max(0, math.floor((total_width - width) / 2)),
    zindex = 60,
  }
  if opts.title and opts.title ~= "" then
    win_opts.title = " " .. opts.title .. " "
    win_opts.title_pos = "center"
  end
  if opts.footer and opts.footer ~= "" then
    win_opts.footer = " " .. opts.footer .. " "
    win_opts.footer_pos = "center"
  end

  local win = vim.api.nvim_open_win(buf, true, win_opts)
  vim.wo[win].cursorline = opts.cursorline ~= false
  vim.wo[win].wrap = opts.wrap == true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"

  for _, highlight in ipairs(opts.highlights or {}) do
    local line = highlight.line
    if line and line >= 1 and line <= #lines then
      local mark_opts = { line_hl_group = highlight.group }
      if highlight.col or highlight.end_col then
        mark_opts.line_hl_group = nil
        mark_opts.hl_group = highlight.group
        mark_opts.end_col = highlight.end_col
      end
      pcall(vim.api.nvim_buf_set_extmark, buf, M.ns, line - 1, highlight.col or 0, mark_opts)
    end
  end

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    if opts.on_close then
      pcall(opts.on_close)
    end
  end

  local map_opts = { buffer = buf, silent = true, nowait = true }
  if opts.close_key ~= false then
    vim.keymap.set("n", "q", close, map_opts)
    vim.keymap.set("n", "<Esc>", close, map_opts)
  end
  for _, mapping in ipairs(opts.keymaps or {}) do
    local rhs = mapping.fn or mapping.rhs
    if rhs then
      vim.keymap.set(mapping.mode or "n", mapping.lhs, rhs, map_opts)
    end
  end

  M._last = { buf = buf, win = win, close = close }
  return buf, win, close
end

function M.close(win)
  win = win or (M._last and M._last.win)
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
    return true
  end
  return false
end

-- Show lines in a scrollable floating window with a close key.
function M.info(title, lines, opts)
  opts = opts or {}
  return M.open({
    lines = lines,
    title = title,
    width = opts.width,
    height = opts.height,
    filetype = opts.filetype,
    highlights = opts.highlights,
    keymaps = opts.keymaps,
    footer = opts.footer or "q: close",
  })
end

function M.notify_error(message)
  utils.error(message)
end

return M
