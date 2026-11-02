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

local function require_forge()
  local ok, forge = pcall(require, "forge")
  if not ok then
    vim.notify("Forge.nvim failed to load: " .. tostring(forge), vim.log.levels.ERROR)
    return nil
  end
  forge._ensure_setup()
  return forge
end

local function require_ui()
  if not require_forge() then
    return nil
  end
  return require("forge.ui")
end

local function notify_error(message)
  vim.notify("Forge: " .. tostring(message), vim.log.levels.ERROR)
end

local function project_names()
  local registry = require("forge.core.registry")
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
  local registry = require("forge.core.registry")
  local fs = require("forge.core.filesystem")
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
  if vim.g.forge_commands_registered then
    return
  end
  vim.g.forge_commands_registered = true

  local function command(name, fn, opts)
    opts = opts or {}
    opts.desc = opts.desc or ("Forge: " .. name)
    vim.api.nvim_create_user_command(name, function(args)
      local ok, err = pcall(fn, args)
      if not ok then
        notify_error(err)
      end
    end, opts)
  end

  command("Forge", function()
    local ui = require_ui()
    if ui then
      ui.dashboard()
    end
  end, {
    nargs = 0,
    desc = "Forge: open the dashboard",
  })

  command("ForgeCreate", function()
    local ui = require_ui()
    if ui then
      ui.create()
    end
  end, {
    nargs = 0,
    desc = "Forge: create a new project",
  })

  command("ForgeOpen", function(args)
    local forge = require_forge()
    if not forge then
      return
    end
    local project_mod = require("forge.core.project")
    local target = args.args ~= "" and args.args or nil
    local record = nil
    if target then
      record = find_project(target)
      if not record then
        notify_error("no project or directory named '" .. target .. "'")
        return
      end
    else
      record = require("forge.ui.picker").project("Open project")
    end
    if not record then
      return
    end
    local ok, err = project_mod.open(record)
    if ok then
      vim.notify("Forge: opened " .. record.path, vim.log.levels.INFO)
    else
      notify_error(err)
    end
  end, {
    nargs = "?",
    desc = "Forge: open a project",
    complete = function(arglead)
      local names = project_names()
      local dirs = vim.fn.getcompletion(arglead, "dir")
      return vim.list_extend(names, dirs)
    end,
  })

  command("ForgeRecent", function()
    local forge = require_forge()
    if not forge then
      return
    end
    local registry = require("forge.core.registry")
    local records = registry.recent(10)
    if #records == 0 then
      vim.notify("Forge: no recent projects.", vim.log.levels.INFO)
      return
    end
    local record = require("forge.ui.picker").project("Recent projects", { records = records })
    if record then
      local ok, err = require("forge.core.project").open(record)
      if ok then
        vim.notify("Forge: opened " .. record.path, vim.log.levels.INFO)
      else
        notify_error(err)
      end
    end
  end, {
    nargs = 0,
    desc = "Forge: open a recent project",
  })

  command("ForgeDetect", function(args)
    local ui = require_ui()
    if ui then
      ui.detect(args.args ~= "" and args.args or nil)
    end
  end, {
    nargs = "?",
    desc = "Forge: detect project markers",
    complete = "dir",
  })

  for _, kind in ipairs({ "Build", "Test", "Run", "Clean" }) do
    local current_kind = kind
    command("Forge" .. current_kind, function()
      local forge = require_forge()
      if not forge then
        return
      end
      local managers = {
        Build = require("forge.managers.build"),
        Test = require("forge.managers.test"),
        Run = require("forge.managers.run"),
        Clean = require("forge.managers.build"),
      }
      local manager = managers[current_kind]
      manager.execute(current_kind:lower(), {})
    end, {
      nargs = 0,
      desc = "Forge: " .. current_kind:lower() .. " the current project",
    })
  end

  command("ForgeTools", function(args)
    local forge = require_forge()
    if not forge then
      return
    end
    local ui = require("forge.ui")
    if args.args == "" then
      ui.runtimes()
      return
    end

    local runtimes = require("forge.runtimes")
    local installer = require("forge.runtimes.installer")
    local utils = require("forge.utils")
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
      lines[#lines + 1] = "Use :ForgeInstall " .. tool .. " to confirm and run it."
    elseif plan then
      lines[#lines + 1] = "Install: " .. tostring(plan.reason or "not available")
      if plan.hint then
        lines[#lines + 1] = "Hint: " .. plan.hint
      end
    end
    require("forge.ui.window").info("Forge Tool: " .. tool, lines)
  end, {
    nargs = "?",
    desc = "Forge: runtime and tool status",
    complete = function(arglead)
      local runtimes = require("forge.runtimes")
      local matches = {}
      for _, tool in ipairs(runtimes.tool_names()) do
        if tool:sub(1, #arglead) == arglead then
          matches[#matches + 1] = tool
        end
      end
      return matches
    end,
  })

  command("ForgeDoctor", function()
    local ui = require_ui()
    if ui then
      ui.doctor()
    end
  end, {
    nargs = 0,
    desc = "Forge: open the health check",
  })

  command("ForgeInstall", function(args)
    local ui = require_ui()
    if not ui then
      return
    end
    ui.install(args.args ~= "" and args.args or nil)
  end, {
    nargs = "?",
    desc = "Forge: install a tool after confirmation",
    complete = function(arglead)
      local runtimes = require("forge.runtimes")
      local matches = {}
      for _, tool in ipairs(runtimes.tool_names()) do
        if tool:sub(1, #arglead) == arglead then
          matches[#matches + 1] = tool
        end
      end
      return matches
    end,
  })

  command("ForgeTemplates", function(args)
    local ui = require_ui()
    if ui then
      ui.templates(args.args ~= "" and args.args or nil)
    end
  end, {
    nargs = "?",
    desc = "Forge: browse project templates",
    complete = function(arglead)
      local languages = require("forge.languages")
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

  command("ForgeRemove", function(args)
    local forge = require_forge()
    if not forge then
      return
    end
    local registry = require("forge.core.registry")
    local record = find_project(args.args)
    if args.args == "" then
      record = require("forge.ui.picker").project("Unregister project")
    end
    if not record then
      return
    end
    if not record.id then
      vim.notify("Forge: that project is not registered.", vim.log.levels.WARN)
      return
    end
    local confirmed = require("forge.ui.select").confirm(
      ("Remove '%s' from the registry?\n\n  %s\n\nProject files are NOT deleted."):format(record.name, record.path),
      { default = false }
    )
    if not confirmed then
      return
    end
    local removed, err = registry.unregister(record.id)
    if removed then
      vim.notify(("Forge: removed '%s' from the registry. Files were kept."):format(removed.name), vim.log.levels.INFO)
    else
      notify_error(err)
    end
  end, {
    nargs = "?",
    desc = "Forge: unregister a project (files are kept)",
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

  command("ForgeCancel", function()
    local ui = require_ui()
    if ui then
      ui.jobs()
    end
  end, {
    nargs = 0,
    desc = "Forge: list and cancel running commands",
  })
end

return M
