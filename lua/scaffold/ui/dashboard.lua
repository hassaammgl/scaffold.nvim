-- The Scaffold dashboard.
--
-- A native floating window with keyboard navigation. When no UI is attached
-- (or in very small terminals), it falls back to vim.ui.select.

local config = require("scaffold.config")
local registry = require("scaffold.core.registry")
local project_mod = require("scaffold.core.project")
local build = require("scaffold.managers.build")
local run_manager = require("scaffold.managers.run")
local test_manager = require("scaffold.managers.test")
local components = require("scaffold.ui.components")
local picker = require("scaffold.ui.picker")
local select = require("scaffold.ui.select")
local input = require("scaffold.ui.input")
local window = require("scaffold.ui.window")
local utils = require("scaffold.utils")

local M = {}

local WIDTH = 76

local function open_project(record)
  if not record then
    return
  end
  local ok, err = project_mod.open(record)
  if ok then
    utils.notify("Opened " .. record.path)
  else
    utils.error("Scaffold: " .. tostring(err))
  end
end

local function action_open()
  open_project(picker.project("Open project"))
end

local function action_recent()
  local recent = registry.recent(10)
  if #recent == 0 then
    utils.notify("No recent projects yet.")
    return
  end
  open_project(picker.project("Recent projects", { records = recent }))
end

local function action_search()
  local query = input.input("Search projects: ")
  if query == nil or utils.trim(query) == "" then
    return
  end
  local results = registry.search(query)
  if #results == 0 then
    utils.notify(("No projects match '%s'."):format(query))
    return
  end
  open_project(picker.project("Search results", { records = results }))
end

local function action_current()
  local current = project_mod.current()
  if not current then
    utils.notify("No current project. Open or create one first.")
    return
  end
  require("scaffold.ui.screens").project_info(current)
end

local function action_remove()
  local record = picker.project("Unregister project")
  if not record then
    return
  end
  if not record.id then
    utils.notify("That project is not registered.")
    return
  end
  local confirmed = select.confirm(
    ("Remove '%s' from the registry?\n\n  %s\n\nProject files are NOT deleted."):format(record.name, record.path),
    { default = false }
  )
  if not confirmed then
    return
  end
  local removed, err = registry.unregister(record.id)
  if removed then
    utils.notify(("Removed '%s' from the registry. Files were kept."):format(removed.name))
  else
    utils.error("Scaffold: " .. tostring(err))
  end
end

local function project_label()
  local current = project_mod.current()
  return current and current.name or "no current project"
end

local function build_items()
  local screens = require("scaffold.ui.screens")
  return {
    { section = "Projects" },
    { label = "Open project", detail = "choose from the registry", action = action_open },
    { label = "Recent projects", detail = "last opened", action = action_recent },
    { label = "Search projects", detail = "by name, path, or language", action = action_search },
    { label = "Current project", detail = project_label(), action = action_current },
    { section = "Create" },
    {
      label = "New project",
      detail = "guide me through a template",
      action = function()
        require("scaffold.ui.wizard").create()
      end,
    },
    { label = "Browse templates", detail = "inspect what Scaffold can generate", action = screens.browse_templates },
    { section = "Development" },
    {
      label = "Build",
      detail = project_label(),
      action = function()
        build.execute("build")
      end,
    },
    {
      label = "Run",
      detail = project_label(),
      action = function()
        run_manager.execute({})
      end,
    },
    {
      label = "Test",
      detail = project_label(),
      action = function()
        test_manager.execute({})
      end,
    },
    {
      label = "Clean",
      detail = "asks for confirmation",
      action = function()
        build.execute("clean")
      end,
    },
    { label = "Dependencies", detail = "inspect or install with confirmation", action = screens.dependencies },
    { label = "Running commands", detail = "list or cancel", action = screens.jobs },
    { section = "Environment" },
    { label = "Runtimes", detail = "detect installed tools", action = screens.runtimes },
    { label = "Toolchains", detail = "per-language status", action = screens.toolchains },
    { label = "Doctor", detail = "open :checkhealth scaffold", action = screens.doctor },
    { section = "Settings" },
    { label = "Registry and paths", detail = "configuration overview", action = screens.settings },
    { label = "Unregister project", detail = "never deletes files", action = action_remove },
  }
end

local HELP_LINES = {
  "Navigation",
  "  j / k       move",
  "  <CR>        run the selected action",
  "  g?          this help",
  "  q / <Esc>   close",
  "",
  "Commands",
  "  :Scaffold             dashboard",
  "  :ScaffoldCreate       project wizard",
  "  :ScaffoldOpen         open a project",
  "  :ScaffoldRecent       recent projects",
  "  :ScaffoldDetect       detect project markers",
  "  :ScaffoldBuild        build",
  "  :ScaffoldRun          run",
  "  :ScaffoldTest         test",
  "  :ScaffoldClean        clean",
  "  :ScaffoldTools        runtime/tool status",
  "  :ScaffoldDoctor       health check",
  "  :ScaffoldInstall      install a tool (confirmed)",
  "  :ScaffoldTemplates    browse templates",
  "  :ScaffoldRemove       unregister a project",
  "  :ScaffoldCancel       list running commands",
}

local function show_help()
  window.info("Scaffold Help", HELP_LINES, { width = 64, height = math.min(#HELP_LINES, 26) })
end

local function fallback(items)
  local choices = {}
  for _, item in ipairs(items) do
    if item.label then
      choices[#choices + 1] = item
    end
  end
  local chosen = select.choose("Scaffold.nvim", choices, {
    format_item = function(item)
      return item.detail and ("%s — %s"):format(item.label, item.detail) or item.label
    end,
  })
  if chosen and chosen.action then
    local ok, err = pcall(chosen.action)
    if not ok then
      utils.error("Scaffold: " .. tostring(err))
    end
  end
end

function M.open()
  local items = build_items()

  if not window.ui_available() or vim.o.columns < 50 or vim.o.lines < 16 then
    fallback(items)
    return nil
  end

  local lines = {
    components.header("Scaffold.nvim", utils.fmt_path(config.get("projects_dir")), WIDTH),
    components.rule(WIDTH),
    "",
  }
  local highlights = { { line = 1, group = "ScaffoldTitle" } }
  local line_to_item = {}
  local first_item_line = nil

  for _, item in ipairs(items) do
    if item.section then
      lines[#lines + 1] = " " .. item.section
      highlights[#highlights + 1] = { line = #lines, group = "ScaffoldSection" }
    else
      lines[#lines + 1] = components.item(item.label, item.detail, WIDTH)
      line_to_item[#lines] = item
      if not first_item_line then
        first_item_line = #lines
      end
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = " :ScaffoldCreate   :ScaffoldOpen   :ScaffoldBuild   :ScaffoldDoctor"
  highlights[#highlights + 1] = { line = #lines, group = "ScaffoldMuted" }

  local win
  local function run(item)
    if not item or not item.action then
      return
    end
    window.close(win)
    local ok, err = pcall(item.action)
    if not ok then
      utils.error("Scaffold: " .. tostring(err))
    end
  end

  local buf
  buf, win = window.open({
    lines = lines,
    title = "Scaffold",
    width = WIDTH,
    height = math.min(#lines, 34),
    highlights = highlights,
    keymaps = {
      {
        lhs = "<CR>",
        fn = function()
          local cursor = vim.api.nvim_win_get_cursor(0)[1]
          run(line_to_item[cursor])
        end,
      },
      {
        lhs = "g?",
        fn = function()
          window.close(win)
          show_help()
        end,
      },
    },
    footer = "j/k: move   <CR>: select   g?: help   q: close",
  })

  if win and first_item_line then
    pcall(vim.api.nvim_win_set_cursor, win, { first_item_line, 2 })
  end
  return buf, win
end

return M
