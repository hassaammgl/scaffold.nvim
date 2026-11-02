-- User commands.
--
-- Only commands are registered at startup; each one lazily loads the rest of
-- the plugin and ensures defaults are initialized if the user never called
-- setup(). No global keymaps are installed here.

local M = {}

local function format_timestamp(timestamp)
  if not timestamp then
    return "unknown"
  end
  local ok, result = pcall(os.date, "%Y-%m-%d %H:%M", timestamp)
  return ok and result or "unknown"
end

local function require_scaffold()
  local ok, scaffold = pcall(require, "scaffold")
  if not ok then
    vim.notify("Scaffold.nvim failed to load: " .. tostring(scaffold), vim.log.levels.ERROR)
    return nil
  end
  scaffold._ensure_setup()
  return scaffold
end

local function require_ui()
  if not require_scaffold() then
    return nil
  end
  return require("scaffold.ui")
end

local function notify_error(message)
  vim.notify("Scaffold: " .. tostring(message), vim.log.levels.ERROR)
end

local function project_names()
  local registry = require("scaffold.core.registry")
  local names = {}
  for _, record in ipairs(registry.all()) do
    names[#names + 1] = record.name
  end
  return names
end

local function find_project(identifier)
  if type(identifier) ~= "string" or identifier == "" then
    return nil
  end
  local registry = require("scaffold.core.registry")
  local fs = require("scaffold.core.filesystem")
  local record = registry.get(identifier)
  if record then
    return record
  end
  record = registry.find_by_path(identifier)
  if record then
    return record
  end
  for _, candidate in ipairs(registry.all()) do
    if candidate.name == identifier then
      return candidate
    end
  end
  local expanded = fs.expand(identifier)
  if fs.is_dir(expanded) then
    return {
      name = fs.basename(expanded),
      path = expanded,
      detected = true,
    }
  end
  return nil
end

function M.register()
  if vim.g.scaffold_commands_registered then
    return
  end
  vim.g.scaffold_commands_registered = true

  local function command(name, fn, opts)
    opts = opts or {}
    opts.desc = opts.desc or ("Scaffold: " .. name)
    vim.api.nvim_create_user_command(name, function(args)
      local ok, err = pcall(fn, args)
      if not ok then
        notify_error(err)
      end
    end, opts)
  end

  command("Scaffold", function()
    local ui = require_ui()
    if ui then
      ui.dashboard()
    end
  end, {
    nargs = 0,
    desc = "Scaffold: open the dashboard",
  })

  command("ScaffoldCreate", function()
    local ui = require_ui()
    if ui then
      ui.create()
    end
  end, {
    nargs = 0,
    desc = "Scaffold: create a new project",
  })

  command("ScaffoldOpen", function(args)
    local scaffold = require_scaffold()
    if not scaffold then
      return
    end
    local project_mod = require("scaffold.core.project")
    local target = args.args ~= "" and args.args or nil
    local record = nil
    if target then
      record = find_project(target)
      if not record then
        notify_error("no project or directory named '" .. target .. "'")
        return
      end
    else
      record = require("scaffold.ui.picker").project("Open project")
    end
    if not record then
      return
    end
    local ok, err = project_mod.open(record)
    if ok then
      vim.notify("Scaffold: opened " .. record.path, vim.log.levels.INFO)
    else
      notify_error(err)
    end
  end, {
    nargs = "?",
    desc = "Scaffold: open a project",
    complete = function(arglead)
      local names = project_names()
      local dirs = vim.fn.getcompletion(arglead, "dir")
      return vim.list_extend(names, dirs)
    end,
  })

  command("ScaffoldRecent", function()
    local scaffold = require_scaffold()
    if not scaffold then
      return
    end
    local registry = require("scaffold.core.registry")
    local records = registry.recent(10)
    if #records == 0 then
      vim.notify("Scaffold: no recent projects.", vim.log.levels.INFO)
      return
    end
    local record = require("scaffold.ui.picker").project("Recent projects", { records = records })
    if record then
      local ok, err = require("scaffold.core.project").open(record)
      if ok then
        vim.notify("Scaffold: opened " .. record.path, vim.log.levels.INFO)
      else
        notify_error(err)
      end
    end
  end, {
    nargs = 0,
    desc = "Scaffold: open a recent project",
  })

  command("ScaffoldDetect", function(args)
    local ui = require_ui()
    if ui then
      ui.detect(args.args ~= "" and args.args or nil)
    end
  end, {
    nargs = "?",
    desc = "Scaffold: detect project markers",
    complete = "dir",
  })

  for _, kind in ipairs({ "Build", "Test", "Run", "Clean" }) do
    local current_kind = kind
    command("Scaffold" .. current_kind, function()
      local scaffold = require_scaffold()
      if not scaffold then
        return
      end
      local managers = {
        Build = require("scaffold.managers.build"),
        Test = require("scaffold.managers.test"),
        Run = require("scaffold.managers.run"),
        Clean = require("scaffold.managers.build"),
      }
      local manager = managers[current_kind]
      manager.execute(current_kind:lower(), {})
    end, {
      nargs = 0,
      desc = "Scaffold: " .. current_kind:lower() .. " the current project",
    })
  end

  command("ScaffoldTools", function(args)
    local scaffold = require_scaffold()
    if not scaffold then
      return
    end
    local ui = require("scaffold.ui")
    if args.args == "" then
      ui.runtimes()
      return
    end

    local runtimes = require("scaffold.runtimes")
    local installer = require("scaffold.runtimes.installer")
    local utils = require("scaffold.utils")
    local tool = args.args
    local info = runtimes.info(tool)
    local plan = installer.plan(tool)
    local lines = {
      "Tool: " .. tool,
      "Found: " .. (info and info.found and "yes" or "no"),
      "Path: " .. ((info and info.path) or "-"),
      "Version: " .. ((info and info.version) or "-"),
      "Checked: " .. format_timestamp(info and info.checked_at),
      "",
    }
    if plan and plan.argv then
      lines[#lines + 1] = "Install command:"
      lines[#lines + 1] = "  " .. utils.display_argv(plan.argv)
      lines[#lines + 1] = "Use :ScaffoldInstall " .. tool .. " to confirm and run it."
    elseif plan then
      lines[#lines + 1] = "Install: " .. tostring(plan.reason or "not available")
      if plan.hint then
        lines[#lines + 1] = "Hint: " .. plan.hint
      end
    end
    require("scaffold.ui.window").info("Scaffold Tool: " .. tool, lines)
  end, {
    nargs = "?",
    desc = "Scaffold: runtime and tool status",
    complete = function(arglead)
      local runtimes = require("scaffold.runtimes")
      local matches = {}
      for _, tool in ipairs(runtimes.tool_names()) do
        if tool:sub(1, #arglead) == arglead then
          matches[#matches + 1] = tool
        end
      end
      return matches
    end,
  })

  command("ScaffoldDoctor", function()
    local ui = require_ui()
    if ui then
      ui.doctor()
    end
  end, {
    nargs = 0,
    desc = "Scaffold: open the health check",
  })

  command("ScaffoldInstall", function(args)
    local ui = require_ui()
    if not ui then
      return
    end
    ui.install(args.args ~= "" and args.args or nil)
  end, {
    nargs = "?",
    desc = "Scaffold: install a tool after confirmation",
    complete = function(arglead)
      local runtimes = require("scaffold.runtimes")
      local matches = {}
      for _, tool in ipairs(runtimes.tool_names()) do
        if tool:sub(1, #arglead) == arglead then
          matches[#matches + 1] = tool
        end
      end
      return matches
    end,
  })

  command("ScaffoldTemplates", function(args)
    local ui = require_ui()
    if ui then
      ui.templates(args.args ~= "" and args.args or nil)
    end
  end, {
    nargs = "?",
    desc = "Scaffold: browse project templates",
    complete = function(arglead)
      local languages = require("scaffold.languages")
      languages.load_builtins()
      local matches = {}
      for _, id in ipairs(languages.ids()) do
        if id:sub(1, #arglead) == arglead then
          matches[#matches + 1] = id
        end
      end
      return matches
    end,
  })

  command("ScaffoldRemove", function(args)
    local scaffold = require_scaffold()
    if not scaffold then
      return
    end
    local registry = require("scaffold.core.registry")
    local record = find_project(args.args)
    if args.args == "" then
      record = require("scaffold.ui.picker").project("Unregister project")
    end
    if not record then
      return
    end
    if not record.id then
      vim.notify("Scaffold: that project is not registered.", vim.log.levels.WARN)
      return
    end
    local confirmed = require("scaffold.ui.select").confirm(
      ("Remove '%s' from the registry?\n\n  %s\n\nProject files are NOT deleted."):format(record.name, record.path),
      { default = false }
    )
    if not confirmed then
      return
    end
    local removed, err = registry.unregister(record.id)
    if removed then
      vim.notify(("Scaffold: removed '%s' from the registry. Files were kept."):format(removed.name), vim.log.levels.INFO)
    else
      notify_error(err)
    end
  end, {
    nargs = "?",
    desc = "Scaffold: unregister a project (files are kept)",
    complete = function(arglead)
      local names = project_names()
      local matches = {}
      for _, name in ipairs(names) do
        if name:sub(1, #arglead) == arglead then
          matches[#matches + 1] = name
        end
      end
      return matches
    end,
  })

  command("ScaffoldCancel", function()
    local ui = require_ui()
    if ui then
      ui.jobs()
    end
  end, {
    nargs = 0,
    desc = "Scaffold: list and cancel running commands",
  })
end

return M
