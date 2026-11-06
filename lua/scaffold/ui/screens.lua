-- Read-only and small interactive screens used by commands and the dashboard.

local fs = require("scaffold.core.filesystem")
local registry = require("scaffold.core.registry")
local project_mod = require("scaffold.core.project")
local detector = require("scaffold.core.detector")
local process = require("scaffold.core.process")
local runtimes = require("scaffold.runtimes")
local installer = require("scaffold.runtimes.installer")
local toolchains = require("scaffold.toolchains")
local templates = require("scaffold.templates")
local managers = {
  build = require("scaffold.managers.build"),
  dependencies = require("scaffold.managers.dependencies"),
}
local components = require("scaffold.ui.components")
local picker = require("scaffold.ui.picker")
local select = require("scaffold.ui.select")
local window = require("scaffold.ui.window")
local config = require("scaffold.config")
local constants = require("scaffold.constants")
local utils = require("scaffold.utils")

local M = {}

local WIDTH = 78

local function header(title, subtitle)
  return {
    components.header(title, subtitle, WIDTH),
    components.rule(WIDTH),
    "",
  }
end

function M.runtimes(opts)
  opts = opts or {}
  local detected = runtimes.detect(runtimes.tool_names(), { refresh = opts.refresh == true })
  local order = { "c", "js", "python", "java", "vcs" }
  local names = {
    c = "C / C++",
    js = "JavaScript / TypeScript",
    python = "Python",
    java = "Java",
    vcs = "Version control",
  }

  local lines = header("Scaffold.nvim — Runtimes", "r: refresh   i: install   q: close")
  local highlights = { { line = 1, group = "ScaffoldTitle" } }
  local installed, missing = 0, 0

  for _, category in ipairs(order) do
    local group = {}
    for _, tool in ipairs(runtimes.tool_names()) do
      local definition = runtimes.tools[tool]
      if (definition.category or "other") == category then
        group[#group + 1] = tool
      end
    end
    if #group > 0 then
      lines[#lines + 1] = " " .. names[category]
      highlights[#highlights + 1] = { line = #lines, group = "ScaffoldSection" }
      for _, tool in ipairs(group) do
        local info = detected[tool]
        if info and info.found then
          installed = installed + 1
        else
          missing = missing + 1
        end
        local status = components.status(info and info.found, info and info.version)
        lines[#lines + 1] = ("   %-20s %-22s %s"):format(
          info and info.label or tool,
          utils.truncate(info and info.path or "-", 40),
          status
        )
        if not (info and info.found) then
          highlights[#highlights + 1] = { line = #lines, group = "ScaffoldMuted" }
        end
      end
      lines[#lines + 1] = ""
    end
  end

  lines[#lines + 1] = ("Installed: %d    Missing: %d"):format(installed, missing)
  highlights[#highlights + 1] = { line = #lines, group = "ScaffoldAccent" }

  local close
  local buf, win
  buf, win, close = window.open({
    lines = lines,
    title = "Scaffold Runtimes",
    width = WIDTH,
    height = math.min(#lines, 30),
    highlights = highlights,
    keymaps = {
      {
        lhs = "r",
        fn = function()
          close()
          M.runtimes({ refresh = true })
        end,
      },
      {
        lhs = "i",
        fn = function()
          local tool = picker.tool("Install tool")
          if tool then
            close()
            installer.install(tool)
          end
        end,
      },
    },
    footer = "q: close   r: refresh   i: install",
  })
  return buf, win
end

function M.toolchains(language)
  if not language then
    local chosen = picker.language("Toolchain language")
    if not chosen then
      return nil
    end
    language = chosen.id
  end

  local status, err = toolchains.status(language)
  if not status then
    utils.warn("Scaffold: " .. tostring(err))
    return nil
  end

  local lines = header("Scaffold.nvim — Toolchain: " .. status.name, "r: refresh   i: install   q: close")
  local highlights = { { line = 1, group = "ScaffoldTitle" } }
  local missing_required = 0

  for _, group in ipairs(status.groups) do
    lines[#lines + 1] = " " .. group.name
    highlights[#highlights + 1] = { line = #lines, group = "ScaffoldSection" }
    for _, tool in ipairs(group.tools) do
      local required = tool.required and "required" or "optional"
      lines[#lines + 1] = ("   %-18s %-10s %-22s %s"):format(
        tool.label,
        required,
        components.status(tool.found, tool.version),
        utils.truncate(tool.path or "-", 32)
      )
      if not tool.found then
        highlights[#highlights + 1] = { line = #lines, group = tool.required and "ScaffoldError" or "ScaffoldMuted" }
        if tool.required then
          missing_required = missing_required + 1
        end
      end
    end
    lines[#lines + 1] = ""
  end

  lines[#lines + 1] = missing_required > 0
      and ("%d required tool(s) missing. Use i to inspect installation."):format(missing_required)
    or "All required tools are installed."
  highlights[#lines + 1] = { line = #lines, group = missing_required > 0 and "ScaffoldWarn" or "ScaffoldOk" }

  local win
  local buf
  buf, win = window.open({
    lines = lines,
    title = "Scaffold Toolchain",
    width = WIDTH,
    height = math.min(#lines, 30),
    highlights = highlights,
    keymaps = {
      {
        lhs = "r",
        fn = function()
          window.close(win)
          M.toolchains(language)
        end,
      },
      {
        lhs = "i",
        fn = function()
          local tool = picker.tool("Install tool")
          if tool then
            window.close(win)
            installer.install(tool)
          end
        end,
      },
    },
    footer = "q: close   r: refresh   i: install",
  })
  return buf, win
end

function M.template_details(template)
  local lines = header("Scaffold.nvim — Template: " .. template.name, "<CR>: create   q: close")
  local highlights = { { line = 1, group = "ScaffoldTitle" } }

  lines[#lines + 1] = components.kv("ID", template.id, WIDTH)
  lines[#lines + 1] = components.kv("Language", template.language, WIDTH)
  lines[#lines + 1] = components.kv("Version", tostring(template.version or 1), WIDTH)
  lines[#lines + 1] = components.kv("Description", template.description or "-", WIDTH)
  if template.runtime_options and #template.runtime_options > 0 then
    lines[#lines + 1] = components.kv("Runtimes", table.concat(template.runtime_options, ", "), WIDTH)
  end
  if template.build_systems and #template.build_systems > 0 then
    lines[#lines + 1] = components.kv("Build systems", table.concat(template.build_systems, ", "), WIDTH)
  end
  lines[#lines + 1] = ""

  if template.options and next(template.options) then
    lines[#lines + 1] = " Options"
    highlights[#highlights + 1] = { line = #lines, group = "ScaffoldSection" }
    for _, name in ipairs(utils.sorted_keys(template.options)) do
      local definition = template.options[name]
      local detail = definition.type or "input"
      if definition.values then
        detail = detail .. " [" .. table.concat(definition.values, ", ") .. "]"
      end
      lines[#lines + 1] = ("   %-16s %s (default: %s)"):format(name, detail, tostring(definition.default))
    end
    lines[#lines + 1] = ""
  end

  lines[#lines + 1] = " Files"
  highlights[#highlights + 1] = { line = #lines, group = "ScaffoldSection" }
  for _, path in ipairs(utils.sorted_keys(template.files)) do
    lines[#lines + 1] = "   " .. path
  end
  lines[#lines + 1] = ""

  if template.commands and next(template.commands) then
    lines[#lines + 1] = " Commands"
    highlights[#highlights + 1] = { line = #lines, group = "ScaffoldSection" }
    for _, kind in ipairs({ "configure", "build", "test", "run", "clean" }) do
      local command = template.commands[kind]
      if command then
        local preview = type(command) == "function" and "(resolved at creation)" or utils.display_argv(command)
        lines[#lines + 1] = ("   %-10s %s"):format(kind, preview)
      end
    end
  end

  if template.install_commands then
    lines[#lines + 1] = ""
    lines[#lines + 1] = " Dependencies are not installed automatically."
    highlights[#highlights + 1] = { line = #lines, group = "ScaffoldMuted" }
  end

  local close
  local buf, win
  buf, win, close = window.open({
    lines = lines,
    title = "Scaffold Template",
    width = WIDTH,
    height = math.min(#lines, 32),
    highlights = highlights,
    keymaps = {
      {
        lhs = "<CR>",
        fn = function()
          close()
          require("scaffold.ui.wizard").create({ language = template.language, template = template.id })
        end,
      },
    },
    footer = "q: close   <CR>: create project with this template",
  })
  return buf, win
end

function M.templates(language)
  local chosen_language = nil
  if language then
    chosen_language = require("scaffold.languages").get(language)
  else
    chosen_language = picker.language("Template language")
  end
  if not chosen_language then
    return nil
  end
  local template = picker.template("Template", chosen_language.id)
  if not template then
    return nil
  end
  return M.template_details(template)
end

-- Show template details for an already chosen template.
function M.browse_templates()
  return M.templates(nil)
end

function M.project_info(project)
  project = project or project_mod.current()
  if not project then
    utils.notify("No current project. Open or create one first.")
    return nil
  end

  local lines = header("Scaffold.nvim — Project", "b: build   r: run   t: test   o: open   q: close")
  local highlights = { { line = 1, group = "ScaffoldTitle" } }
  local path = project.path or ""
  local exists = fs.is_dir(path)

  lines[#lines + 1] = components.kv("Name", project.name or "?", WIDTH)
  lines[#lines + 1] = components.kv("Path", utils.fmt_path(path), WIDTH)
  local exists_line = #lines + 1
  lines[#lines + 1] = components.kv("Exists", exists and "yes" or "no (missing)", WIDTH)
  lines[#lines + 1] = components.kv("Registered", project.id and "yes" or "no (detected)", WIDTH)
  lines[#lines + 1] = components.kv("Language", project.language or "-", WIDTH)
  lines[#lines + 1] = components.kv("Template", project.template or "-", WIDTH)
  lines[#lines + 1] = components.kv("Runtime", project.runtime or "-", WIDTH)
  lines[#lines + 1] = components.kv("Build system", project.build_system or managers.build.detect_build_system(path, project) or "-", WIDTH)
  lines[#lines + 1] = components.kv("Last opened", utils.format_time(project.last_opened), WIDTH)
  if project.id then
    local record = registry.get(project.id)
    if record then
      lines[#lines + 1] = components.kv("Registered at", utils.format_time(record.created_at), WIDTH)
    end
  end
  if not exists then
    highlights[#highlights + 1] = { line = exists_line, group = "ScaffoldError" }
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = " Commands"
  highlights[#highlights + 1] = { line = #lines, group = "ScaffoldSection" }
  local commands = project.commands or {}
  local any = false
  for _, kind in ipairs({ "configure", "build", "test", "run", "clean" }) do
    local value = commands[kind]
    if value then
      any = true
      local argv = value
      local cwd = nil
      if type(value) == "table" and not utils.is_list(value) and value.argv then
        argv = value.argv
        cwd = value.cwd
      end
      cwd = cwd or commands[kind .. "_cwd"]
      local line = ("   %-10s %s"):format(kind, utils.display_argv(argv))
      if cwd then
        line = line .. ("  (cwd: %s)"):format(cwd)
      end
      lines[#lines + 1] = line
    end
  end
  if not any then
    lines[#lines + 1] = "   (none stored; resolved from project config, template, or build system)"
  end

  local config_path = project_mod.config_path(path)
  lines[#lines + 1] = ""
  lines[#lines + 1] = components.kv("Project config", config_path and utils.fmt_path(config_path) or "none", WIDTH)
  if config_path and config_path:match("%.lua$") then
    lines[#lines + 1] = "   Executable Lua: approval is required before it is loaded."
    highlights[#highlights + 1] = { line = #lines, group = "ScaffoldWarn" }
  end

  local win
  local function run_kind(kind)
    window.close(win)
    managers.build.execute(kind, { project = project })
  end

  local buf
  buf, win = window.open({
    lines = lines,
    title = "Scaffold Project",
    width = WIDTH,
    height = math.min(#lines, 32),
    highlights = highlights,
    keymaps = {
      { lhs = "b", fn = function() run_kind("build") end },
      { lhs = "r", fn = function() run_kind("run") end },
      { lhs = "t", fn = function() run_kind("test") end },
      {
        lhs = "o",
        fn = function()
          window.close(win)
          local ok, err = project_mod.open(project)
          if ok then
            utils.notify("Opened " .. path)
          else
            utils.error("Scaffold: " .. tostring(err))
          end
        end,
      },
    },
    footer = "q: close   b: build   r: run   t: test   o: open",
  })
  return buf, win
end

function M.detect(path)
  path = path or vim.uv.cwd()
  local result, err = detector.detect(path)
  if not result then
    utils.warn("Scaffold: " .. tostring(err))
    return nil
  end
  local lines = header("Scaffold.nvim — Detection", "q: close")
  lines = vim.list_extend(lines, detector.summary(result))
  local highlights = { { line = 1, group = "ScaffoldTitle" } }
  return window.open({
    lines = lines,
    title = "Scaffold Detection",
    width = WIDTH,
    height = math.min(#lines, 26),
    highlights = highlights,
    footer = "q: close",
  })
end

function M.settings()
  local data = registry.load()
  local lines = header("Scaffold.nvim — Settings", "e: edit registry   p: prune missing   q: close")
  local highlights = { { line = 1, group = "ScaffoldTitle" } }
  local project_count = 0
  for _ in pairs(data.projects) do
    project_count = project_count + 1
  end

  lines[#lines + 1] = components.kv("Neovim", tostring(vim.version()), WIDTH)
  lines[#lines + 1] = components.kv("Schema version", tostring(constants.SCHEMA_VERSION), WIDTH)
  lines[#lines + 1] = components.kv("Projects directory", utils.fmt_path(config.get("projects_dir")), WIDTH)
  lines[#lines + 1] = components.kv("Registry", utils.fmt_path(registry.path()), WIDTH)
  lines[#lines + 1] = components.kv("Registered projects", tostring(project_count), WIDTH)
  lines[#lines + 1] = components.kv("Templates directory", config.get("templates_dir") and utils.fmt_path(config.get("templates_dir")) or "none", WIDTH)
  lines[#lines + 1] = components.kv("Confirm installs", tostring(config.get("confirm_before_install")), WIDTH)
  lines[#lines + 1] = components.kv("Runtime cache (s)", tostring(config.get("runtime_cache_ttl")), WIDTH)
  lines[#lines + 1] = ""
  lines[#lines + 1] = " Change these values in require(\"scaffold\").setup({ ... })."
  highlights[#highlights + 1] = { line = #lines, group = "ScaffoldMuted" }
  lines[#lines + 1] = " Project files are never deleted by Scaffold."
  highlights[#highlights + 1] = { line = #lines, group = "ScaffoldMuted" }

  local _, missing = registry.check_paths()
  if #missing > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = (" %d project(s) point to missing directories."):format(#missing)
    highlights[#highlights + 1] = { line = #lines, group = "ScaffoldWarn" }
  end

  local close
  local buf, win
  buf, win, close = window.open({
    lines = lines,
    title = "Scaffold Settings",
    width = WIDTH,
    height = math.min(#lines, 24),
    highlights = highlights,
    keymaps = {
      {
        lhs = "e",
        fn = function()
          close()
          pcall(vim.cmd, "edit " .. vim.fn.fnameescape(registry.path()))
        end,
      },
      {
        lhs = "p",
        fn = function()
          local removed = registry.prune_missing(true)
          if not removed or #removed == 0 then
            utils.notify("No missing project paths to prune.")
            return
          end
          if select.confirm(("Remove %d missing project(s) from the registry?\n\nProject files are NOT deleted."):format(#removed), { default = false }) then
            registry.prune_missing(false)
            close()
            utils.notify(("Removed %d stale registry entr%s."):format(#removed, #removed == 1 and "y" or "ies"))
          end
        end,
      },
    },
    footer = "q: close   e: edit registry   p: prune missing",
  })
  return buf, win
end

function M.dependencies(project)
  project = project or project_mod.current()
  if not project then
    project = picker.project("Dependencies for project")
  end
  if not project then
    return nil
  end

  local action = select.choose("Dependencies: " .. (project.name or "?"), {
    "Inspect dependency workflows",
    "Install dependencies (with confirmation)",
    "Cancel",
  })
  if action == nil or action == "Cancel" then
    return nil
  end
  if action == "Inspect dependency workflows" then
    local lines = managers.dependencies.preview(project)
    return window.open({
      lines = lines,
      title = "Scaffold Dependencies",
      width = WIDTH,
      height = math.min(#lines, 28),
      footer = "q: close",
    })
  end
  return managers.dependencies.install(project)
end

function M.jobs()
  local jobs = process.list_jobs()
  if #jobs == 0 then
    utils.notify("No Scaffold commands are running.")
    return nil
  end
  local job = select.choose("Running commands", jobs, {
    format_item = function(entry)
      return ("%s  [%s]  %s  (pid %d)"):format(
        entry.label or "command",
        tostring(entry.type or "terminal"),
        utils.display_argv(entry.argv),
        entry.id
      )
    end,
  })
  if not job then
    return nil
  end
  if select.confirm(("Cancel %s?\n\n%s"):format(job.label or "command", utils.display_argv(job.argv)), { default = false }) then
    local ok, err = process.cancel(job.id)
    if ok then
      utils.notify("Cancelled " .. (job.label or "command") .. ".")
    else
      utils.error("Scaffold: " .. tostring(err))
    end
  end
end

function M.install(tool)
  if not tool then
    local missing = {}
    for _, name in ipairs(runtimes.tool_names()) do
      if not runtimes.is_available(name) then
        missing[#missing + 1] = name
      end
    end
    if #missing == 0 then
      utils.notify("All known tools are installed.")
      return nil
    end
    tool = picker.tool("Install tool", missing)
  end
  if not tool then
    return nil
  end

  local plan = installer.plan(tool)
  if not plan then
    return nil
  end
  if plan.installed then
    utils.notify(("%s is already installed."):format(tool))
    return nil
  end
  if not plan.argv then
    local lines = header("Scaffold.nvim — Install: " .. tool, "q: close")
    lines[#lines + 1] = "No automatic installation is available."
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Reason: " .. tostring(plan.reason)
    if plan.hint then
      lines[#lines + 1] = "Hint: " .. plan.hint
    end
    return window.open({
      lines = lines,
      title = "Scaffold Install",
      width = WIDTH,
      height = math.min(#lines, 12),
      footer = "q: close",
    })
  end
  return installer.install(tool)
end

function M.doctor()
  local ok, err = pcall(vim.cmd, "checkhealth scaffold")
  if not ok then
    utils.error("Scaffold: could not open health check: " .. tostring(err))
  end
end

return M
