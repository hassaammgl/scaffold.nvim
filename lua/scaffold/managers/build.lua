-- Build command resolution and execution.
--
-- Resolution order:
--   1. explicit argv (API)
--   2. project configuration (.scaffold.json / approved .scaffold.lua)
--   3. registry commands (recorded at creation or user-updated)
--   4. template commands (re-rendered with stored options)
--   5. build-system heuristics
--
-- Project-provided commands require confirmation once per session.

local config = require("scaffold.config")
local fs = require("scaffold.core.filesystem")
local validator = require("scaffold.core.validator")
local process = require("scaffold.core.process")
local registry = require("scaffold.core.registry")
local project_mod = require("scaffold.core.project")
local detector = require("scaffold.core.detector")
local templates = require("scaffold.templates")
local renderer = require("scaffold.templates.renderer")
local utils = require("scaffold.utils")

local M = {}

M._confirmed = {}

-- Built-in defaults used for projects that were not created from a template.
M.DEFAULTS = {
  cmake = {
    configure = { "cmake", "-S", ".", "-B", "build", "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON" },
    build = { "cmake", "--build", "build" },
    test = { "ctest", "--test-dir", "build", "--output-on-failure" },
    clean = { "cmake", "--build", "build", "--target", "clean" },
  },
  make = {
    build = { "make" },
    test = { "make", "test" },
    clean = { "make", "clean" },
  },
  ninja = {
    build = { "ninja", "-C", "build" },
    clean = { "ninja", "-C", "build", "-t", "clean" },
  },
  npm = {
    build = { "npm", "run", "build" },
    test = { "npm", "test" },
    run = { "npm", "start" },
  },
  pnpm = {
    build = { "pnpm", "run", "build" },
    test = { "pnpm", "test" },
    run = { "pnpm", "start" },
  },
  yarn = {
    build = { "yarn", "build" },
    test = { "yarn", "test" },
    run = { "yarn", "start" },
  },
  bun = {
    build = { "bun", "run", "build" },
    test = { "bun", "test" },
    run = { "bun", "run", "start" },
  },
  pip = {
    test = { "python3", "-m", "pytest" },
  },
  pytest = {
    test = { "python3", "-m", "pytest" },
  },
  maven = {
    build = { "mvn", "-q", "-DskipTests", "package" },
    test = { "mvn", "-q", "test" },
    run = { "mvn", "-q", "exec:java" },
    clean = { "mvn", "-q", "clean" },
  },
  gradle = {
    build = { "gradle", "build" },
    test = { "gradle", "test" },
    run = { "gradle", "run" },
    clean = { "gradle", "clean" },
  },
  javac = {
    build = { "javac", "-d", "out", "src/Main.java" },
    run = { "java", "-cp", "out", "Main" },
  },
  cargo = {
    build = { "cargo", "build" },
    test = { "cargo", "test" },
    run = { "cargo", "run" },
    clean = { "cargo", "clean" },
  },
  go = {
    build = { "go", "build", "./..." },
    test = { "go", "test", "./..." },
    run = { "go", "run", "." },
  },
}

local function recorded(project)
  if project and project.id then
    return registry.get(project.id) or project
  end
  return project
end

local function lockfile_manager(path)
  if fs.is_file(fs.join(path, "bun.lock")) or fs.is_file(fs.join(path, "bun.lockb")) then
    return "bun"
  end
  if fs.is_file(fs.join(path, "pnpm-lock.yaml")) then
    return "pnpm"
  end
  if fs.is_file(fs.join(path, "yarn.lock")) then
    return "yarn"
  end
  if fs.is_file(fs.join(path, "package-lock.json")) then
    return "npm"
  end
  return nil
end

function M.detect_build_system(path, project)
  project = recorded(project)
  if project and project.build_system and project.build_system ~= "" then
    return project.build_system
  end

  local detection = detector.detect(path, { max_depth = 2 })
  if detection then
    for _, candidate in ipairs(detection.candidates or {}) do
      if candidate.root == fs.normalize(path) and candidate.build_system then
        return candidate.build_system
      end
    end
    if detection.build_system then
      return detection.build_system
    end
  end

  if fs.is_file(fs.join(path, "pom.xml")) then
    return "maven"
  elseif fs.is_file(fs.join(path, "build.gradle")) or fs.is_file(fs.join(path, "build.gradle.kts")) then
    return "gradle"
  elseif fs.is_file(fs.join(path, "CMakeLists.txt")) then
    return "cmake"
  elseif fs.is_file(fs.join(path, "Makefile")) then
    return "make"
  elseif fs.is_file(fs.join(path, "package.json")) then
    return lockfile_manager(path) or "npm"
  elseif fs.is_file(fs.join(path, "pyproject.toml")) or fs.is_file(fs.join(path, "requirements.txt")) then
    return "pip"
  elseif fs.is_file(fs.join(path, "Cargo.toml")) then
    return "cargo"
  elseif fs.is_file(fs.join(path, "go.mod")) then
    return "go"
  end
  return nil
end

-- Find an executable produced by the build system.
function M.find_binary(path, project)
  project = recorded(project)
  local names = {}
  if project and project.name then
    names[#names + 1] = utils.slugify(project.name)
    names[#names + 1] = project.name
  end
  local base = fs.basename(path)
  names[#names + 1] = utils.slugify(base)
  names[#names + 1] = base

  local candidates = {}
  for _, name in ipairs(names) do
    candidates[#candidates + 1] = fs.join(path, "build", name)
    candidates[#candidates + 1] = fs.join(path, name)
  end
  candidates[#candidates + 1] = fs.join(path, "a.out")

  for _, candidate in ipairs(candidates) do
    if fs.is_file(candidate) and process.executable(candidate) then
      local relative = candidate:sub(#fs.normalize(path) + 2)
      return "./" .. relative
    end
  end
  return nil
end

function M.default_commands(build_system, kind, path, project)
  if not build_system then
    return nil
  end
  local defaults = M.DEFAULTS[build_system]
  if not defaults then
    return nil
  end

  if kind == "run" and (build_system == "cmake" or build_system == "make" or build_system == "ninja") then
    local binary = M.find_binary(path, project)
    if binary then
      return { binary }
    end
    return nil
  end

  local command = defaults[kind]
  if not command then
    return nil
  end
  return vim.deepcopy(command)
end

local function normalize_configured(value, root)
  local cwd = nil
  if type(value) == "table" and not utils.is_list(value) and value.argv ~= nil then
    cwd = value.cwd
    value = value.argv
  end
  local ok, err = validator.command(value)
  if not ok then
    return nil, nil, err
  end
  if cwd ~= nil then
    if type(cwd) ~= "string" then
      return nil, nil, "command cwd must be a string"
    end
    cwd = fs.join(root, cwd)
  end
  return vim.deepcopy(value), cwd, nil
end

local function template_context(record, path)
  local template = record.template and templates.get(record.template)
  if not template then
    return nil, nil
  end
  local ctx = renderer.context(template, {
    project_name = record.name,
    project_slug = utils.slugify(record.name),
    project_path = path,
    language = record.language,
    runtime = record.runtime,
    build_system = record.build_system,
    package_manager = record.package_manager,
    options = record.options,
  })
  return template, ctx
end

-- Returns a command specification:
-- { argv, cwd, source, kind, build_system, confirm, note }
function M.resolve(project, kind, opts)
  opts = opts or {}
  project = recorded(project or project_mod.current())
  if not project then
    return nil, "no current project"
  end
  local path = fs.expand(project.path)
  if not fs.is_dir(path) then
    return nil, "project directory does not exist: " .. path
  end

  if opts.argv ~= nil then
    local ok, err = validator.command(opts.argv)
    if not ok then
      return nil, err
    end
    return {
      argv = vim.deepcopy(opts.argv),
      cwd = opts.cwd and fs.expand(opts.cwd) or path,
      source = "explicit",
      kind = kind,
      confirm = kind == "clean",
    }
  end

  if project_mod.has_config(path) then
    local project_config, config_meta = project_mod.config(path, { approve = true })
    if project_config and project_config.commands and project_config.commands[kind] then
      local argv, cwd, cfg_err = normalize_configured(project_config.commands[kind], path)
      if not argv then
        return nil, cfg_err
      end
      return {
        argv = argv,
        cwd = cwd or path,
        source = config_meta and config_meta.source or "project configuration",
        confirm = true,
        kind = kind,
      }
    end
  end

  -- A freshly created CMake project has no build directory yet. Configure
  -- before compiling, even when a build command was recorded at creation.
  local known_build_system = project.build_system or M.detect_build_system(path, project)
  if kind == "build" and known_build_system == "cmake" and not fs.is_dir(fs.join(path, "build")) then
    local configure = project.commands and project.commands.configure
    local argv, cwd, configure_err = nil, nil, nil
    if configure then
      argv, cwd, configure_err = normalize_configured(configure, path)
    end
    if configure_err then
      return nil, configure_err
    end
    return {
      argv = argv or vim.deepcopy(M.DEFAULTS.cmake.configure),
      cwd = cwd or path,
      source = configure and "registry" or "heuristic",
      kind = kind,
      build_system = known_build_system,
      confirm = false,
      note = "Build directory missing: configuring with CMake. Run Build again to compile.",
    }
  end

  local stored = project.commands and project.commands[kind]
  if stored then
    local argv, cwd, stored_err = normalize_configured(stored, path)
    if not argv then
      return nil, stored_err
    end
    local stored_cwd = project.commands[kind .. "_cwd"]
    if stored_cwd and not cwd then
      cwd = fs.join(path, stored_cwd)
    end
    return {
      argv = argv,
      cwd = cwd or path,
      source = "registry",
      kind = kind,
      confirm = kind == "clean",
    }
  end

  local template, ctx = template_context(project, path)
  if template and template.commands and template.commands[kind] then
    local argv, cwd, err = renderer.resolve_command(template.commands[kind], ctx)
    if err then
      return nil, err
    end
    if argv then
      return {
        argv = argv,
        cwd = cwd and fs.join(path, cwd) or path,
        source = "template",
        kind = kind,
        confirm = kind == "clean",
      }
    end
  end

  local build_system = M.detect_build_system(path, project)
  if kind == "build" and build_system == "cmake" and not fs.is_dir(fs.join(path, "build")) then
    return {
      argv = vim.deepcopy(M.DEFAULTS.cmake.configure),
      cwd = path,
      source = "heuristic",
      kind = kind,
      build_system = build_system,
      confirm = false,
      note = "Build directory missing: configuring with CMake. Run Build again to compile.",
    }
  end

  local command = M.default_commands(build_system, kind, path, project)
  if not command then
    if kind == "run" and (build_system == "cmake" or build_system == "make") then
      return nil, "no executable found; build the project first"
    end
    return nil, ("no %s command for this project (build system: %s)"):format(kind, tostring(build_system))
  end

  return {
    argv = command,
    cwd = path,
    source = "heuristic",
    kind = kind,
    build_system = build_system,
    confirm = kind == "clean",
  }
end

local function confirmation_key(spec, path)
  return table.concat({ path, spec.kind or "", table.concat(spec.argv, "\0") }, "\1")
end

function M.confirm(spec, path, opts)
  opts = opts or {}
  local key = confirmation_key(spec, path)
  local always_confirm = spec.kind == "clean"
  if spec.confirm and (always_confirm or not M._confirmed[key]) then
    local select = require("scaffold.ui.select")
    local approved = select.confirm(
      ("Run project %s command?\n\n  %s\n\nWorking directory:\n  %s\n\nSource: %s"):format(
        spec.kind or "command",
        utils.display_argv(spec.argv),
        path,
        spec.source or "unknown"
      ),
      { default = false }
    )
    if not approved then
      return false
    end
    if not always_confirm then
      M._confirmed[key] = true
    end
  end
  if opts.confirm then
    local select = require("scaffold.ui.select")
    if not select.confirm(("Run:\n\n  %s\n\nin %s?"):format(utils.display_argv(spec.argv), path), { default = false }) then
      return false
    end
  end
  return true
end

function M.execute(kind, opts)
  opts = opts or {}
  local spec, err = M.resolve(opts.project, kind, opts)
  if not spec then
    utils.warn("Scaffold: " .. tostring(err))
    return nil, err
  end

  if not M.confirm(spec, spec.cwd, { confirm = opts.confirm }) then
    utils.notify("Scaffold: " .. kind .. " cancelled.")
    return nil, "cancelled"
  end

  if spec.note then
    utils.notify(spec.note)
  end

  local job_id, buf = process.terminal(spec.argv, {
    cwd = spec.cwd,
    label = kind,
    split = opts.split,
  })
  if not job_id then
    utils.error("Scaffold: could not start " .. kind .. ": " .. tostring(buf))
    return nil, buf
  end

  utils.notify(("Scaffold %s: %s\ncwd: %s"):format(kind, utils.display_argv(spec.argv), spec.cwd))
  return job_id, spec
end

function M.preview(project, kind)
  local spec, err = M.resolve(project, kind)
  if not spec then
    return { ("%s: %s"):format(kind, tostring(err)) }
  end
  return {
    ("%s command:"):format(kind),
    "  " .. utils.display_argv(spec.argv),
    "working directory: " .. spec.cwd,
    "source: " .. tostring(spec.source),
  }
end

function M.reset_confirmations()
  M._confirmed = {}
end

return M
