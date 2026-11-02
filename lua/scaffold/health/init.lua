-- :checkhealth scaffold

local config = require("scaffold.config")
local fs = require("scaffold.core.filesystem")
local registry = require("scaffold.core.registry")
local runtimes = require("scaffold.runtimes")
local installer = require("scaffold.runtimes.installer")
local templates = require("scaffold.templates")
local languages = require("scaffold.languages")

local M = {}

local function health()
  return vim.health or require("vim.health")
end

local function report(level, message)
  local h = health()
  local fn = h[level] or h.info
  if fn then
    pcall(fn, message)
  end
end

local function start(name)
  local h = health()
  if h and h.start then
    pcall(h.start, name)
  end
end

function M.check()
  start("scaffold")

  report("info", ("Scaffold.nvim %s"):format(require("scaffold").version or "dev"))
  report("info", ("Neovim %s"):format(tostring(vim.version())))

  if vim.fn.has("nvim-0.11") == 1 then
    report("ok", "Neovim 0.11+ is available")
  elseif vim.fn.has("nvim-0.10") == 1 then
    report("warn", "Neovim 0.10 detected; Scaffold targets 0.11+ (some features may differ)")
  else
    report("error", "Neovim 0.11+ is required")
  end

  -- Registry
  local registry_path = registry.path()
  report("info", "Registry: " .. registry_path)
  if fs.exists(registry_path) then
    if fs.is_readable(registry_path) then
      report("ok", "Registry is readable")
    else
      report("error", "Registry is not readable")
    end
  else
    report("info", "Registry does not exist yet (it will be created on first project registration)")
  end

  local data = registry.load(true)
  if data.schema_version == require("scaffold.constants").SCHEMA_VERSION then
    report("ok", "Registry schema version " .. tostring(data.schema_version))
  else
    report("warn", "Unexpected registry schema version " .. tostring(data.schema_version))
  end

  local valid, missing = registry.check_paths()
  if #missing > 0 then
    report("warn", ("%d registered project path(s) are missing"):format(#missing))
    for _, record in ipairs(missing) do
      report("info", ("  %s: %s"):format(record.name or "?", record.path or "?"))
    end
    report("info", "Run :Scaffold and use Settings > Registry, or :ScaffoldRemove, to clean metadata (files are never deleted)")
  else
    report("ok", ("All %d registered project path(s) exist"):format(#valid))
  end

  -- Projects directory
  local projects_dir = config.get("projects_dir")
  if fs.is_dir(projects_dir) then
    report("ok", "Projects directory exists: " .. projects_dir)
  else
    report("warn", "Projects directory does not exist: " .. tostring(projects_dir))
  end

  -- Templates
  templates.load_builtins()
  local template_count = #templates.list()
  if template_count > 0 then
    report("ok", ("%d template(s) registered"):format(template_count))
  else
    report("error", "No templates registered")
  end
  local templates_dir = config.get("templates_dir")
  if templates_dir then
    if fs.is_dir(templates_dir) then
      report("ok", "External templates directory exists: " .. templates_dir)
    else
      report("warn", "External templates directory does not exist: " .. templates_dir)
    end
  end

  languages.load_builtins()
  report("ok", ("%d language(s) registered"):format(#languages.list()))

  -- Tools
  if vim.fn.executable("git") == 1 then
    report("ok", "git is available")
  else
    report("warn", "git is not available (optional, used for project initialization)")
  end

  local manager, family = installer.manager()
  if manager then
    report("ok", ("Package manager for installation: %s (%s)"):format(manager, tostring(family)))
  else
    report("warn", "No supported package manager detected (Scaffold supports pacman and apt)")
  end

  local required = { "g++", "node", "python3", "java" }
  local found = 0
  for _, tool in ipairs(required) do
    if runtimes.is_available(tool) then
      found = found + 1
    end
  end
  report("info", ("%d/%d common runtimes found on PATH (version checks are not run by the health check)"):format(found, #required))

  report("info", "Scaffold never installs runtimes or dependencies automatically and never deletes project files.")
end

return M
