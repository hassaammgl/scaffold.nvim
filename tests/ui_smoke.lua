-- Headless UI smoke test.
--
-- Forces the floating-window path (headless Neovim has no attached UI),
-- stubs native selection/input, opens the dashboard and major screens, then
-- walks the wizard through its preview and <CR> callback.
--
--   nvim --headless --clean -u NONE -l tests/ui_smoke.lua
--
-- This is intentionally separate from tests/run.lua: it is a UI wiring test,
-- not a substitute for the validation and safety specs.

vim.opt.runtimepath:prepend(vim.fn.getcwd())

local root = vim.fn.tempname()
local projects = root .. "/projects"
require("scaffold.core.filesystem").mkdirp(projects)

local scaffold = require("scaffold")
scaffold.setup({
  projects_dir = projects,
  registry_path = root .. "/registry.json",
  open_after_create = false,
  notify_on_exit = false,
})

local window = require("scaffold.ui.window")
window.ui_available = function()
  return true
end

local select = require("scaffold.ui.select")
select.choose = function(_, choices)
  return choices[1]
end
select.confirm = function(_, opts)
  return opts and opts.default == true
end

local inputs = {
  ["Project name: "] = "ui-wizard",
  ["Parent directory: "] = projects,
}
vim.ui.select = function(items, opts, on_choice)
  local prompt = opts and opts.prompt or ""
  if prompt:find("Git repository", 1, true) or prompt:find("Open the project", 1, true) then
    on_choice("No")
  else
    on_choice(items[1])
  end
end
vim.ui.input = function(opts, on_confirm)
  on_confirm(inputs[opts.prompt] or opts.default)
end

local function buffer_text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

local function close_last()
  local last = window._last
  if last then
    pcall(vim.api.nvim_win_close, last.win, true)
  end
end

-- Dashboard.
local dashboard = require("scaffold.ui.dashboard")
local dbuf, dwin = dashboard.open()
assert(dbuf and dwin, "dashboard did not open")
local dashboard_text = buffer_text(dbuf)
assert(dashboard_text:find("Scaffold.nvim", 1, true), "dashboard title missing")
assert(dashboard_text:find("New project", 1, true), "dashboard create item missing")
assert(dashboard_text:find("Doctor", 1, true), "dashboard doctor item missing")
close_last()

-- Screens.
local screens = require("scaffold.ui.screens")
assert(screens.runtimes({}), "runtime screen did not open")
close_last()

for _, language in ipairs({ "cpp", "python" }) do
  assert(screens.toolchains(language), "toolchain screen did not open for " .. language)
  close_last()
end

assert(screens.detect(vim.fn.getcwd()), "detection screen did not open")
close_last()

assert(screens.settings(), "settings screen did not open")
close_last()

-- Wizard: choose the first language/template and the first option defaults,
-- then activate the preview's <CR> mapping.
local wizard = require("scaffold.ui.wizard")
local wbuf = assert(wizard.create(), "wizard did not open")
local text = buffer_text(wbuf)
assert(text:find("Preview", 1, true), "wizard preview missing")
assert(text:find("ui-wizard", 1, true), "wizard preview does not show the project name")

local enter
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(wbuf, "n")) do
  if mapping.lhs == "<CR>" and mapping.callback then
    enter = mapping.callback
  end
end
assert(enter, "wizard preview has no <CR> callback")
enter()

local record = require("scaffold.core.registry").find_by_path(projects .. "/ui-wizard")
assert(record, "wizard did not register the project")
assert(#require("scaffold.core.filesystem").list_details(record.path) > 0, "wizard did not write template files")

-- Project and dependency screens.
assert(screens.project_info(record), "project info screen did not open")
close_last()

assert(screens.dependencies(record), "dependency inspection screen did not open")
close_last()

-- Installing an already-present tool is a safe no-op.
screens.install("git")

print("Scaffold.nvim UI smoke test passed")
print("created: " .. record.path)
vim.fn.delete(root, "rf")
