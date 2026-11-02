-- Configuration handling for Forge.nvim.
-- setup() always merges over defaults; calling it twice is safe.

local constants = require("forge.constants")
local utils = require("forge.utils")

local M = {}

local function default_projects_dir()
  return vim.fs.joinpath(vim.fn.expand("~"), constants.DEFAULT_PROJECTS_DIRNAME)
end

local function default_registry_path()
  return vim.fs.joinpath(vim.fn.stdpath("data"), constants.DEFAULT_REGISTRY_DIR, "projects.json")
end

M.defaults = {
  -- Where new projects are created. "~" is expanded.
  projects_dir = default_projects_dir(),

  -- Project registry metadata. Never the source of truth for a project.
  registry_path = default_registry_path(),

  -- Optional list of directories containing trusted external template modules.
  templates_dir = nil,

  -- Ask before running package-manager install commands.
  confirm_before_install = true,

  -- Ask before the first execution of a project-provided command in a session.
  confirm_before_project_commands = true,

  -- Ask before opening a project after creating it.
  open_after_create = true,

  -- Do not load .forge.lua automatically; require approval for every session.
  allow_lua_project_config = true,

  -- Runtime version cache lifetime in seconds. 0 disables caching.
  runtime_cache_ttl = 300,

  -- Terminal split used by build/run/test commands.
  terminal_split = "botright 14split",

  -- Optional user keymaps, e.g. { dashboard = "<leader>fp" }.
  -- Forge never installs global keymaps unless this table is populated.
  keymaps = {},

  -- Health/UI preference: hide version checks for missing tools (they are
  -- always shown as "missing" regardless).
  notify_on_exit = true,
}

M.options = vim.deepcopy(M.defaults)
M._setup_done = false

local function expand_user_path(path)
  if type(path) ~= "string" or path == "" then
    return path
  end
  local expanded = vim.fn.expand(path)
  if not expanded:match("^/") and not expanded:match("^%a:[/\\]") then
    expanded = vim.fs.joinpath(vim.uv.cwd(), expanded)
  end
  return vim.fs.normalize(expanded)
end

local function validate_string(name, value)
  if value ~= nil and type(value) ~= "string" then
    utils.warn(("forge.setup: '%s' must be a string; ignoring"):format(name))
    return false
  end
  return true
end

function M.setup(opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    error("forge.setup: options must be a table")
  end

  local merged = utils.deep_merge(M.defaults, opts)

  if validate_string("projects_dir", merged.projects_dir) and merged.projects_dir then
    merged.projects_dir = expand_user_path(merged.projects_dir)
  else
    merged.projects_dir = expand_user_path(M.defaults.projects_dir)
  end

  if validate_string("registry_path", merged.registry_path) and merged.registry_path then
    merged.registry_path = expand_user_path(merged.registry_path)
  else
    merged.registry_path = expand_user_path(M.defaults.registry_path)
  end

  if validate_string("templates_dir", merged.templates_dir) and merged.templates_dir then
    merged.templates_dir = expand_user_path(merged.templates_dir)
  end

  if type(merged.runtime_cache_ttl) ~= "number" or merged.runtime_cache_ttl < 0 then
    utils.warn("forge.setup: 'runtime_cache_ttl' must be a non-negative number; using default")
    merged.runtime_cache_ttl = M.defaults.runtime_cache_ttl
  end

  if type(merged.keymaps) ~= "table" then
    utils.warn("forge.setup: 'keymaps' must be a table; using empty keymaps")
    merged.keymaps = {}
  end

  if merged.templates_dir and not vim.uv.fs_stat(merged.templates_dir) then
    utils.warn(("forge.setup: templates_dir does not exist: %s"):format(merged.templates_dir))
  end

  M.options = merged
  M._setup_done = true
  return M.options
end

-- Returns a single option when a key is given, otherwise the whole table.
function M.get(key)
  if key == nil then
    return M.options
  end
  return M.options[key]
end

function M.reset()
  M.options = vim.deepcopy(M.defaults)
  M._setup_done = false
end

return M
