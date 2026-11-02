-- Project creation, opening, current-project resolution, and project config.
--
-- Creation is plan-first: nothing is written until validation succeeds, and
-- existing files are never overwritten. .scaffold.lua is never loaded silently.

local config = require("scaffold.config")
local fs = require("scaffold.core.filesystem")
local validator = require("scaffold.core.validator")
local process = require("scaffold.core.process")
local events = require("scaffold.core.events")
local sandbox = require("scaffold.core.sandbox")
local registry = require("scaffold.core.registry")
local detector = require("scaffold.core.detector")
local languages = require("scaffold.languages")
local templates = require("scaffold.templates")
local renderer = require("scaffold.templates.renderer")
local utils = require("scaffold.utils")

local M = {}

M._approved_lua_configs = {}

local function resolve_parent(opts)
  local parent = opts.parent_dir or opts.projects_dir or config.get("projects_dir")
  if type(parent) ~= "string" or parent == "" then
    return nil, "a parent directory is required"
  end
  parent = fs.expand(parent)
  local ok, err = validator.absolute_path(parent)
  if not ok then
    return nil, err
  end
  return parent
end

local function resolve_option(template, field, opts_field, provided)
  if provided ~= nil then
    if type(provided) ~= "string" then
      return nil, ("'%s' must be a string"):format(field)
    end
    local choices = template[opts_field] or {}
    if #choices > 0 and not utils.tbl_contains(choices, provided) then
      return nil, ("'%s' must be one of: %s"):format(field, table.concat(choices, ", "))
    end
    return provided
  end
  if template["default_" .. field] then
    return template["default_" .. field]
  end
  local choices = template[opts_field] or {}
  return choices[1]
end

local function normalize_install_commands(template, ctx)
  local definition = template.install_commands
  if definition == nil then
    return {}
  end
  if type(definition) == "function" then
    local ok, result = pcall(definition, ctx)
    if not ok then
      return {}, "install_commands function failed: " .. tostring(result)
    end
    definition = result
  end
  if type(definition) ~= "table" then
    return {}, "install_commands must be a table"
  end

  local commands = {}
  for _, entry in ipairs(definition) do
    local argv = entry
    local label = nil
    if type(entry) == "table" and not utils.is_list(entry) then
      argv = entry.argv
      label = entry.label
    end
    local ok, err = validator.command(argv)
    if not ok then
      return {}, "install command: " .. err
    end
    commands[#commands + 1] = {
      label = label or utils.display_argv(argv),
      argv = vim.deepcopy(argv),
    }
  end
  return commands
end

-- Build a complete, side-effect-free creation plan.
function M.plan(opts)
  opts = opts or {}
  languages.load_builtins()
  templates.load_builtins()

  local name_ok, name_or_err = validator.project_name(opts.name)
  if not name_ok then
    return nil, name_or_err
  end
  local name = name_or_err

  if type(opts.language) ~= "string" or opts.language == "" then
    return nil, "a language is required"
  end
  local language = languages.get(opts.language)
  if not language then
    return nil, "unknown language: " .. tostring(opts.language)
  end

  local template = nil
  if opts.template ~= nil then
    template = templates.get(opts.template)
    if not template then
      return nil, "unknown template: " .. tostring(opts.template)
    end
  else
    template = templates.default_for(language.id)
  end
  if not template then
    return nil, "no template available for language: " .. language.id
  end
  if template.language ~= language.id then
    return nil, ("template '%s' belongs to language '%s', not '%s'"):format(template.id, template.language, language.id)
  end

  local parent, parent_err = resolve_parent(opts)
  if not parent then
    return nil, parent_err
  end
  local parent_exists = fs.is_dir(parent)
  local destination = fs.join(parent, name)
  local dest_ok, dest_or_err = validator.destination(destination, { allow_missing_parent = not parent_exists })
  if not dest_ok then
    return nil, dest_or_err
  end
  destination = dest_or_err

  local options, options_err = renderer.apply_defaults(template, opts.options)
  if not options then
    return nil, options_err
  end

  local package_manager, pm_err = resolve_option(template, "package_manager", "package_managers", opts.package_manager)
  if pm_err then
    return nil, pm_err
  end
  local build_system, bs_err = resolve_option(template, "build_system", "build_systems", opts.build_system)
  if bs_err then
    return nil, bs_err
  end

  local runtime = opts.runtime
  if runtime == nil then
    runtime = template.default_runtime
  end
  if runtime == nil and language.runtimes then
    runtime = language.runtimes[1]
  end
  if runtime ~= nil then
    if type(runtime) ~= "string" then
      return nil, "'runtime' must be a string"
    end
    local runtime_choices = template.runtime_options or language.runtimes or {}
    if #runtime_choices > 0 and not utils.tbl_contains(runtime_choices, runtime) then
      return nil, ("'runtime' must be one of: %s"):format(table.concat(runtime_choices, ", "))
    end
  end

  local ctx = renderer.context(template, {
    project_name = name,
    project_slug = utils.slugify(name),
    project_path = destination,
    language = language.id,
    runtime = runtime,
    build_system = build_system,
    package_manager = package_manager,
    options = options,
    author = opts.author or vim.env.USER,
  })

  local rendered = renderer.plan(template, ctx, destination)
  local errors = vim.deepcopy(rendered.errors or {})

  local commands = {}
  for _, kind in ipairs({ "build", "test", "run", "clean", "configure" }) do
    local definition = template.commands and template.commands[kind]
    if definition ~= nil then
      local argv, cwd, err = renderer.resolve_command(definition, ctx)
      if err then
        errors[#errors + 1] = ("command '%s': %s"):format(kind, err)
      elseif argv then
        commands[kind] = argv
        if cwd then
          commands[kind .. "_cwd"] = cwd
        end
      end
    end
  end

  local install_commands, install_err = normalize_install_commands(template, ctx)
  if install_err then
    errors[#errors + 1] = install_err
  end

  return {
    name = name,
    slug = utils.slugify(name),
    destination = destination,
    parent = parent,
    create_parent = not parent_exists,
    language = language.id,
    language_name = language.name,
    template = template.id,
    template_name = template.name,
    runtime = runtime,
    build_system = build_system,
    package_manager = package_manager,
    options = options,
    context = ctx,
    operations = rendered.operations,
    commands = commands,
    install_commands = install_commands,
    git = opts.git == true,
    errors = errors,
  }
end

-- Create the project. Returns project, metadata or nil, error, metadata.
function M.create(opts)
  opts = opts or {}
  local plan, plan_err = M.plan(opts)
  if not plan then
    return nil, plan_err
  end
  if #plan.errors > 0 then
    return nil, "cannot create project: " .. table.concat(plan.errors, "; "), { plan = plan }
  end
  if opts.dry_run then
    return plan
  end

  if plan.create_parent then
    local ok, err = fs.mkdirp(plan.parent)
    if not ok then
      return nil, "could not create parent directory: " .. tostring(err), { plan = plan }
    end
  end

  local render_plan = {
    template = templates.get(plan.template),
    context = plan.context,
    destination = plan.destination,
    operations = plan.operations,
    errors = {},
  }
  local result, apply_err, partial = renderer.apply(render_plan, { overwrite = opts.overwrite == true })
  if not result then
    return nil, apply_err, { plan = plan, created = partial and partial.created or {}, destination = plan.destination }
  end

  local meta = {
    plan = plan,
    created = result.created,
    skipped = result.skipped,
    destination = plan.destination,
    install_commands = plan.install_commands,
    git = nil,
  }

  if opts.git then
    if not process.executable("git") then
      meta.git = { ok = false, reason = "git is not installed" }
      utils.warn("Scaffold: project created, but git is not installed; skipping 'git init'.")
    else
      local git_result = process.run_sync({ "git", "init", plan.destination }, { timeout = 15000 })
      if git_result and git_result.code == 0 then
        meta.git = { ok = true }
      else
        meta.git = {
          ok = false,
          reason = git_result and (git_result.stderr or git_result.stdout or "git init failed") or "git init failed",
        }
        utils.warn("Scaffold: project created, but 'git init' failed.")
      end
    end
  end

  local record, register_err = registry.register({
    name = plan.name,
    path = plan.destination,
    language = plan.language,
    template = plan.template,
    runtime = plan.runtime,
    build_system = plan.build_system,
    package_manager = plan.package_manager,
    commands = plan.commands,
    options = plan.options,
    description = plan.template_name,
    source = "scaffold",
  })
  if not record then
    return nil, "project files were created, but registration failed: " .. tostring(register_err), meta
  end

  meta.project = record
  events.emit("project_created", { project = record, plan = plan })

  if opts.open == true then
    M.open(record)
  end

  return record, meta
end

-- Open a project directory: change Neovim's cwd and update last_opened.
-- Accepts a registry record, an id/path string, or a directory path.
function M.open(target)
  local record = nil
  if type(target) == "table" then
    record = target
  elseif type(target) == "string" then
    record = registry.get(target) or registry.find_by_path(target)
    if not record then
      local path = fs.expand(target)
      if not fs.is_dir(path) then
        return nil, "not a directory: " .. tostring(path)
      end
      local detection = detector.detect(path)
      record = {
        name = fs.basename(path),
        path = path,
        language = detection and detection.language or nil,
        build_system = detection and detection.build_system or nil,
        detected = true,
      }
    end
  else
    return nil, "project or path required"
  end

  if type(record.path) ~= "string" or not fs.is_dir(record.path) then
    return nil, "project directory does not exist: " .. tostring(record and record.path)
  end

  local ok, err = pcall(vim.fn.chdir, record.path)
  if not ok then
    return nil, "could not change directory: " .. tostring(err)
  end

  if record.id then
    registry.touch(record.id)
    record = registry.get(record.id) or record
  end

  events.emit("project_opened", { project = record })
  return true, record
end

-- Resolve the project containing the current buffer (or cwd).
function M.current()
  local buffer = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buffer)
  local start = nil
  if name and name ~= "" and not name:match("^%a+://") then
    start = fs.dirname(name)
  end
  if not start or not fs.is_dir(start) then
    start = vim.uv.cwd()
  end

  local record = registry.find_containing(start)
  if record then
    return record
  end
  record = registry.find_containing(vim.uv.cwd())
  if record then
    return record
  end

  local detection = detector.detect(start)
  if not detection or not detection.best then
    detection = detector.detect(vim.uv.cwd())
  end
  if detection and detection.best then
    return {
      id = nil,
      name = fs.basename(detection.root),
      path = detection.root,
      language = detection.language,
      build_system = detection.build_system,
      detected = true,
      detection = detection,
    }
  end
  return nil
end

function M.config_path(path)
  if type(path) ~= "string" then
    return nil
  end
  local json = fs.join(path, ".scaffold.json")
  local lua = fs.join(path, ".scaffold.lua")
  if fs.is_file(json) then
    return json
  end
  if fs.is_file(lua) then
    return lua
  end
  return nil
end

local function read_json_config(path)
  local data, err = fs.read(path)
  if not data then
    return nil, err
  end
  local ok, decoded = pcall(vim.json.decode, data)
  if not ok or type(decoded) ~= "table" then
    return nil, "invalid JSON project configuration: " .. path
  end
  return decoded
end

local function approve_lua(path)
  if M._approved_lua_configs[path] then
    return true
  end
  local select = require("scaffold.ui.select")
  local approved = select.confirm(
    ("This project contains an executable Lua configuration:\n\n  %s\n\nLua configuration can run code when loaded. Only approve projects you trust."):format(path),
    { default = false }
  )
  if approved then
    M._approved_lua_configs[path] = os.time()
    return true
  end
  return false
end

-- Read project configuration.
-- .scaffold.json is declarative and safe, so it is read automatically.
-- .scaffold.lua is executable and requires approval once per session.
function M.config(path, opts)
  opts = opts or {}
  if type(path) ~= "string" or path == "" then
    return nil, "project path is required"
  end
  local root = fs.expand(path)
  if not fs.is_dir(root) then
    return nil, "not a directory: " .. root
  end

  local json_path = fs.join(root, ".scaffold.json")
  if fs.is_file(json_path) then
    local decoded, err = read_json_config(json_path)
    if not decoded then
      return nil, err
    end
    local ok, config_err = validator.project_config(decoded)
    if not ok then
      return nil, config_err
    end
    return decoded, { source = json_path, executable = false }
  end

  local lua_path = fs.join(root, ".scaffold.lua")
  if fs.is_file(lua_path) then
    if config.get("allow_lua_project_config") == false then
      return nil, ".scaffold.lua is disabled by configuration"
    end
    if not opts.approved then
      if opts.approve == false then
        return nil, ".scaffold.lua was not approved"
      end
      if not approve_lua(lua_path) then
        return nil, ".scaffold.lua was not approved"
      end
    end

    local decoded, err = sandbox.load_file(lua_path, ".scaffold.lua")
    if not decoded then
      return nil, err
    end
    local ok, config_err = validator.project_config(decoded)
    if not ok then
      return nil, config_err
    end
    return decoded, { source = lua_path, executable = true }
  end

  return nil, "no project configuration found"
end

function M.has_config(path)
  return M.config_path(path) ~= nil
end

function M.approve_lua(path)
  local lua_path = fs.join(fs.expand(path), ".scaffold.lua")
  if not fs.is_file(lua_path) then
    return false
  end
  return approve_lua(lua_path)
end

function M._reset_approvals()
  M._approved_lua_configs = {}
end

return M
