-- Native project initialization wizard.
--
-- Every step uses vim.ui.select/vim.ui.input, with a floating preview before
-- anything is written. No dependency installation happens automatically.

local config = require("forge.config")
local fs = require("forge.core.filesystem")
local validator = require("forge.core.validator")
local project_mod = require("forge.core.project")
local languages = require("forge.languages")
local templates = require("forge.templates")
local renderer = require("forge.templates.renderer")
local runtimes = require("forge.runtimes")
local components = require("forge.ui.components")
local input = require("forge.ui.input")
local picker = require("forge.ui.picker")
local select = require("forge.ui.select")
local window = require("forge.ui.window")
local utils = require("forge.utils")

local M = {}

local function ordered_values(definition)
  local list = {}
  for _, value in ipairs(definition.values or {}) do
    if value == definition.default then
      table.insert(list, 1, value)
    else
      list[#list + 1] = value
    end
  end
  return list
end

local function choose_option(name, definition)
  local label = definition.label or name
  local option_type = definition.type or "input"
  if option_type == "select" then
    local values = ordered_values(definition)
    if #values == 1 then
      return values[1]
    end
    return select.choose(label, values, {
      format_item = function(value)
        return value == definition.default and (tostring(value) .. " (default)") or tostring(value)
      end,
    })
  elseif option_type == "confirm" then
    return select.confirm(label .. "?", { default = definition.default ~= false })
  end
  return input.validated(label .. ": ", { default = definition.default }, function(value)
    if definition.required and utils.trim(value) == "" then
      return nil, label .. " is required"
    end
    return true, value
  end)
end

local function choose_parent()
  return input.validated("Parent directory: ", {
    default = config.get("projects_dir"),
    completion = "dir",
  }, function(value)
    local ok, expanded = validator.absolute_path(value)
    if not ok then
      return nil, expanded
    end
    if fs.exists(expanded) and not fs.is_dir(expanded) then
      return nil, "path exists but is not a directory: " .. expanded
    end
    return true, expanded
  end)
end

local function show_result(record, meta, opts)
  local lines = {
    components.header("Forge.nvim — Project created", nil, 70),
    components.rule(70),
    "",
    "Project: " .. record.name,
    "Path:    " .. record.path,
    "Files:   " .. tostring(meta and #meta.created or 0) .. " created",
  }
  if meta and meta.skipped and #meta.skipped > 0 then
    lines[#lines + 1] = "Skipped existing files: " .. #meta.skipped
  end
  if opts.git then
    if meta and meta.git and meta.git.ok then
      lines[#lines + 1] = "Git:     initialized"
    elseif meta and meta.git and not meta.git.ok then
      lines[#lines + 1] = "Git:     not initialized (" .. tostring(meta.git.reason) .. ")"
    end
  end

  lines[#lines + 1] = ""
  if meta and meta.install_commands and #meta.install_commands > 0 then
    lines[#lines + 1] = "Dependencies were NOT installed. Run these when ready:"
    for _, command in ipairs(meta.install_commands) do
      lines[#lines + 1] = "  " .. utils.display_argv(command.argv)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Use :Forge to install dependencies with confirmation."
  else
    lines[#lines + 1] = "No dependency installation is required."
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Next: :ForgeBuild, :ForgeRun, :ForgeTest"

  window.open({
    lines = lines,
    title = "Forge",
    width = 72,
    height = math.min(#lines, 20),
    footer = "q: close",
  })
end

function M.create(preset)
  preset = preset or {}
  languages.load_builtins()
  templates.load_builtins()

  local language = nil
  if preset.language then
    language = languages.get(preset.language)
    if not language then
      utils.error("Forge: unknown language: " .. tostring(preset.language))
      return nil
    end
  else
    language = picker.language("Language")
  end
  if not language then
    return nil
  end

  local template = nil
  if preset.template then
    template = templates.get(preset.template)
    if not template then
      utils.error("Forge: unknown template: " .. tostring(preset.template))
      return nil
    end
  else
    template = picker.template("Project type", language.id)
  end
  if not template then
    return nil
  end
  if template.language ~= language.id then
    utils.error(("Forge: template '%s' does not belong to %s"):format(template.id, language.name))
    return nil
  end

  local runtime_choices = template.runtime_options or language.runtimes or {}
  local runtime = nil
  if #runtime_choices == 1 then
    runtime = runtime_choices[1]
  elseif #runtime_choices > 1 then
    runtime = select.choose("Runtime", runtime_choices, {
      format_item = function(tool)
        return ("%s — %s"):format(tool, runtimes.is_available(tool) and "installed" or "not found")
      end,
    })
    if not runtime then
      return nil
    end
  end
  if runtime and not runtimes.is_available(runtime) then
    if not select.confirm(("%s was not found on PATH. Create the project anyway?"):format(runtime), { default = false }) then
      return nil
    end
  end

  local package_manager = nil
  local build_system = nil
  local pm_choices = template.package_managers or {}
  local bs_choices = template.build_systems or {}
  if #pm_choices > 0 then
    local default_pm = template.default_package_manager or pm_choices[1]
    if #pm_choices == 1 then
      package_manager = pm_choices[1]
    else
      package_manager = select.choose("Package manager", pm_choices, {
        format_item = function(manager)
          local label = manager
          if manager == default_pm then
            label = label .. " (default)"
          end
          return label .. " — " .. (runtimes.is_available(manager) and "installed" or "not found")
        end,
      })
      if not package_manager then
        return nil
      end
    end
    build_system = package_manager
  elseif #bs_choices > 0 then
    build_system = template.default_build_system or bs_choices[1]
    if #bs_choices > 1 then
      build_system = select.choose("Build system", bs_choices)
      if not build_system then
        return nil
      end
    end
  end

  local name = nil
  local parent = nil
  while true do
    name = input.validated("Project name: ", { default = template.id:gsub("%-", "_") }, validator.project_name)
    if not name then
      return nil
    end
    parent = choose_parent()
    if not parent then
      return nil
    end
    local destination = fs.join(parent, name)
    local dest_ok, dest_err = validator.destination(destination, { allow_missing_parent = true })
    if dest_ok then
      break
    end
    utils.warn(dest_err)
  end

  local options = {}
  for _, option_name in ipairs(utils.sorted_keys(template.options or {})) do
    local value = choose_option(option_name, template.options[option_name])
    if value == nil then
      return nil
    end
    options[option_name] = value
  end

  local git = select.confirm("Initialize a Git repository?", { default = true })
  local open_after = select.confirm("Open the project after creation?", {
    default = config.get("open_after_create") == true,
  })

  local create_opts = {
    name = name,
    language = language.id,
    template = template.id,
    parent_dir = parent,
    runtime = runtime,
    build_system = build_system,
    package_manager = package_manager,
    options = options,
    git = git,
  }

  local plan, plan_err = project_mod.plan(create_opts)
  if not plan then
    utils.error("Forge: " .. tostring(plan_err))
    return nil
  end
  if #plan.errors > 0 then
    local lines = { "The template could not be rendered:", "" }
    for _, err in ipairs(plan.errors) do
      lines[#lines + 1] = "  " .. err
    end
    window.info("Forge — Template error", lines)
    return nil
  end

  local preview_lines = {
    components.header("Forge.nvim — Preview", nil, 76),
    components.rule(76),
    "",
    "Project:    " .. plan.name,
    "Destination: " .. plan.destination,
    "Language:   " .. language.name,
    "Template:   " .. template.name,
    "Runtime:    " .. tostring(runtime or "default"),
    "Build:      " .. tostring(build_system or "default"),
    "Package:    " .. tostring(package_manager or "none"),
    "Git init:   " .. (git and "yes" or "no"),
  }
  if plan.create_parent then
    preview_lines[#preview_lines + 1] = "Note:       parent directory will be created"
  end
  preview_lines[#preview_lines + 1] = ""

  local template_obj = templates.get(plan.template)
  local render_plan = {
    template = template_obj,
    context = plan.context,
    destination = plan.destination,
    operations = plan.operations,
    errors = {},
  }
  preview_lines = vim.list_extend(preview_lines, renderer.preview_lines(render_plan))
  preview_lines[#preview_lines + 1] = ""
  preview_lines[#preview_lines + 1] = "Nothing is written until you press <CR>."
  preview_lines[#preview_lines + 1] = "Existing files are never overwritten."

  local close
  local function do_create()
    close()
    local record, meta_or_err, meta = project_mod.create(create_opts)
    if not record then
      local message = tostring(meta_or_err)
      if meta and meta.destination then
        message = message .. "\nSome files may exist in " .. meta.destination
      end
      utils.error("Forge: " .. message)
      return
    end
    show_result(record, meta_or_err, { git = git })
    if open_after then
      local opened, open_err = project_mod.open(record)
      if opened then
        utils.notify("Opened " .. record.path)
      else
        utils.warn("Forge: " .. tostring(open_err))
      end
    end
  end

  local buf, win
  buf, win, close = window.open({
    lines = preview_lines,
    title = "Forge Preview",
    width = 76,
    height = math.min(#preview_lines, 32),
    highlights = { { line = 1, group = "ForgeTitle" } },
    keymaps = {
      {
        lhs = "<CR>",
        fn = do_create,
      },
    },
    footer = "q: cancel   <CR>: create project",
  })
  return buf, win
end

return M
