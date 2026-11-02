-- Dependency inspection and installation.
--
-- Forge never installs dependencies automatically. Every command is shown,
-- the user confirms, and commands run asynchronously in an output buffer.

local fs = require("forge.core.filesystem")
local process = require("forge.core.process")
local project_mod = require("forge.core.project")
local build = require("forge.managers.build")
local toolchains = require("forge.toolchains")
local utils = require("forge.utils")

local M = {}

local function node_package_manager(path, project)
  if fs.is_file(fs.join(path, "bun.lock")) or fs.is_file(fs.join(path, "bun.lockb")) then
    return "bun"
  elseif fs.is_file(fs.join(path, "pnpm-lock.yaml")) then
    return "pnpm"
  elseif fs.is_file(fs.join(path, "yarn.lock")) then
    return "yarn"
  elseif fs.is_file(fs.join(path, "package-lock.json")) then
    return "npm"
  end
  return project and project.package_manager or "npm"
end

local function install_argv(manager)
  if manager == "yarn" then
    return { "yarn" }
  elseif manager == "bun" then
    return { "bun", "install" }
  end
  return { manager, "install" }
end

local function python_runtime(project)
  if project and project.runtime then
    return project.runtime
  end
  return "python3"
end

-- Returns a plan: { project, path, build_system, operations, notes, missing }
function M.plan(project, opts)
  opts = opts or {}
  project = project or project_mod.current()
  if not project then
    return nil, "no current project"
  end
  local path = fs.expand(project.path)
  if not fs.is_dir(path) then
    return nil, "project directory does not exist: " .. path
  end

  local operations = {}
  local notes = {}
  local missing = {}
  local build_system = build.detect_build_system(path, project)

  local function add(operation)
    operation.cwd = path
    operations[#operations + 1] = operation
  end

  if fs.is_file(fs.join(path, "package.json")) then
    local manager = node_package_manager(path, project)
    add({
      id = "node-install",
      label = ("Install Node dependencies with %s"):format(manager),
      argv = install_argv(manager),
      kind = "install",
      requires_tool = manager,
    })
    if fs.is_dir(fs.join(path, "node_modules")) then
      notes[#notes + 1] = "node_modules already exists; installation will refresh it."
    end
  elseif fs.is_file(fs.join(path, "pyproject.toml")) or fs.is_file(fs.join(path, "requirements.txt")) then
    local runtime = python_runtime(project)
    local venv = fs.join(path, ".venv")
    local venv_exists = fs.is_dir(venv)
    if not venv_exists then
      add({
        id = "python-venv",
        label = "Create virtual environment (.venv)",
        argv = { runtime, "-m", "venv", ".venv" },
        kind = "venv",
        requires_tool = runtime,
      })
    end
    local pip_argv
    if fs.is_file(fs.join(path, "requirements.txt")) then
      pip_argv = { ".venv/bin/pip", "install", "-r", "requirements.txt" }
    elseif fs.is_file(fs.join(path, "pyproject.toml")) then
      pip_argv = { ".venv/bin/pip", "install", "-e", "." }
    end
    if pip_argv then
      add({
        id = "python-install",
        label = "Install Python project dependencies",
        argv = pip_argv,
        kind = "install",
        requires_tool = "pip",
      })
    end
    if not venv_exists then
      notes[#notes + 1] = "A virtual environment will be created first; dependency installation uses it."
    end
  elseif fs.is_file(fs.join(path, "pom.xml")) then
    add({
      id = "maven-resolve",
      label = "Resolve Maven dependencies",
      argv = { "mvn", "-q", "dependency:resolve" },
      kind = "resolve",
      requires_tool = "mvn",
    })
  elseif fs.is_file(fs.join(path, "build.gradle")) or fs.is_file(fs.join(path, "build.gradle.kts")) then
    add({
      id = "gradle-resolve",
      label = "Resolve Gradle dependencies",
      argv = { "gradle", "dependencies" },
      kind = "resolve",
      requires_tool = "gradle",
    })
  elseif build_system == "cargo" then
    add({
      id = "cargo-fetch",
      label = "Fetch Cargo dependencies",
      argv = { "cargo", "fetch" },
      kind = "resolve",
      requires_tool = "cargo",
    })
  elseif build_system == "go" then
    add({
      id = "go-mod-download",
      label = "Download Go modules",
      argv = { "go", "mod", "download" },
      kind = "resolve",
      requires_tool = "go",
    })
  elseif build_system == "cmake" or build_system == "make" then
    notes[#notes + 1] = "C/C++ projects have no package manager. Missing compilers are reported below."
  else
    notes[#notes + 1] = "No dependency workflow detected for this project."
  end

  -- Report missing required tools instead of installing them silently.
  if project.language then
    local status = toolchains.status(project.language, opts)
    if status then
      for _, group in ipairs(status.groups or {}) do
        for _, tool in ipairs(group.tools or {}) do
          if tool.required and not tool.found then
            missing[#missing + 1] = {
              id = tool.id,
              label = tool.label,
              group = group.name,
            }
          end
        end
      end
    end
  end

  return {
    project = project,
    path = path,
    build_system = build_system,
    operations = operations,
    notes = notes,
    missing = missing,
  }
end

-- Inspect only; never runs anything.
function M.inspect(project, opts)
  return M.plan(project, opts)
end

function M.preview(project)
  local plan, err = M.plan(project)
  if not plan then
    return { tostring(err) }
  end
  local lines = {
    ("Dependencies for %s"):format(plan.project.name or fs.basename(plan.path)),
    "Path: " .. plan.path,
    "Build system: " .. tostring(plan.build_system),
    "",
  }
  if #plan.operations == 0 then
    lines[#lines + 1] = "No install commands detected."
  else
    lines[#lines + 1] = "Planned commands:"
    for _, operation in ipairs(plan.operations) do
      lines[#lines + 1] = "  " .. operation.label
      lines[#lines + 1] = "    " .. utils.display_argv(operation.argv)
    end
  end
  if #plan.missing > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Missing required tools:"
    for _, tool in ipairs(plan.missing) do
      lines[#lines + 1] = ("  %s (%s)"):format(tool.label, tool.group)
    end
    lines[#lines + 1] = "Use :ForgeInstall <tool> to see the package command."
  end
  for _, note in ipairs(plan.notes) do
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Note: " .. note
  end
  return lines
end

local function run_chain(operations, index, path, buf, on_done)
  if index > #operations then
    if on_done then
      on_done(true)
    end
    return
  end
  local operation = operations[index]
  local job_id, err = process.captured(operation.argv, {
    cwd = path,
    buf = buf,
    label = operation.label,
  }, function(result)
    if result and result.code == 0 then
      run_chain(operations, index + 1, path, buf, on_done)
    else
      utils.warn(("Forge: %s failed (exit %s). Remaining commands were not run."):format(
        operation.label,
        tostring(result and result.code)
      ))
      if on_done then
        on_done(false)
      end
    end
  end)
  if not job_id then
    utils.error("Forge: could not start dependency command: " .. tostring(err))
    if on_done then
      on_done(false)
    end
  end
end

-- Confirm and run dependency commands. opts.operations may preselect ops.
function M.install(project, opts)
  opts = opts or {}
  local plan, err = M.plan(project, opts)
  if not plan then
    utils.warn("Forge: " .. tostring(err))
    return nil, err
  end

  if #plan.operations == 0 then
    local message = "Forge: no dependency commands detected."
    if #plan.notes > 0 then
      message = message .. " " .. table.concat(plan.notes, " ")
    end
    utils.notify(message)
    return nil, "nothing to do"
  end

  local operations = opts.operations or plan.operations
  if #operations == 0 then
    return nil, "no operations selected"
  end

  local select = require("forge.ui.select")
  local lines = {
    ("Install dependencies for %s?"):format(plan.project.name or fs.basename(plan.path)),
    "",
    "Working directory:",
    "  " .. plan.path,
    "",
    "Commands:",
  }
  for _, operation in ipairs(operations) do
    lines[#lines + 1] = "  " .. utils.display_argv(operation.argv)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Nothing runs until you confirm. Some commands may download from the network."

  if not select.confirm(table.concat(lines, "\n"), { default = false }) then
    utils.notify("Forge: dependency installation cancelled.")
    return nil, "cancelled"
  end

  local buf = process.open_output("Dependencies — " .. (plan.project.name or fs.basename(plan.path)))
  run_chain(operations, 1, plan.path, buf)
  return true, plan
end

return M
