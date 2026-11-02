-- Input validation. Every filesystem or process boundary in Forge goes
-- through these functions. They never touch the filesystem except for
-- destination checks (which only stat paths).

local constants = require("forge.constants")
local utils = require("forge.utils")
local fs = require("forge.core.filesystem")

local M = {}

local function is_absolute(path)
  return path:match("^/") ~= nil or path:match("^%a:[/\\]") ~= nil
end

function M.project_name(name)
  if type(name) ~= "string" then
    return nil, "project name must be a string"
  end
  name = utils.trim(name)
  if name == "" then
    return nil, "project name is required"
  end
  if #name > constants.MAX_PROJECT_NAME then
    return nil, ("project name must be at most %d characters"):format(constants.MAX_PROJECT_NAME)
  end
  if not name:match(constants.PROJECT_NAME_PATTERN) then
    return nil,
      "project name may only contain letters, digits, '_', '-', and '.' and must start with a letter, digit, or '_'"
  end
  if name:find("..", 1, true) then
    return nil, "project name may not contain '..'"
  end
  if constants.RESERVED_NAMES[name:lower()] then
    return nil, "project name is reserved: " .. name
  end
  return true, name
end

function M.slug(name)
  return utils.slugify(name)
end

-- Validate a template-relative path. Rejects absolute paths, "..", empty
-- segments, NUL bytes, and backslashes.
function M.relative_path(path)
  if type(path) ~= "string" or path == "" then
    return nil, "path must be a non-empty string"
  end
  if #path > constants.MAX_PATH_LENGTH then
    return nil, "path is too long"
  end
  if path:find("%z") then
    return nil, "path contains a NUL byte"
  end
  if path:find("\\", 1, true) then
    return nil, "backslashes are not allowed in template paths"
  end
  if is_absolute(path) then
    return nil, "absolute paths are not allowed in templates"
  end
  for segment in path:gmatch("[^/]+") do
    if segment == "." or segment == ".." then
      return nil, "path traversal is not allowed: " .. path
    end
  end
  if path:match("^/") or path:match("/$") or path:match("//") then
    return nil, "invalid path: " .. path
  end
  return true, path
end

function M.absolute_path(path)
  if type(path) ~= "string" or path == "" then
    return nil, "path must be a non-empty string"
  end
  if #path > constants.MAX_PATH_LENGTH then
    return nil, "path is too long"
  end
  if path:find("%z") then
    return nil, "path contains a NUL byte"
  end
  local expanded = fs.expand(path)
  if not is_absolute(expanded) then
    return nil, "path must be absolute: " .. tostring(expanded)
  end
  return true, expanded
end

-- Validate a directory that Forge intends to create. Options:
--   allow_missing_parent: accept a missing parent as long as its nearest
--   existing ancestor is a directory (project.create may then mkdir it).
function M.destination(path, opts)
  opts = opts or {}
  local ok, expanded = M.absolute_path(path)
  if not ok then
    return nil, expanded
  end
  if expanded == "/" then
    return nil, "refusing to use the filesystem root as a project directory"
  end
  local home = vim.fs.normalize(vim.fn.expand("~"))
  if expanded == home then
    return nil, "refusing to use the home directory as a project directory"
  end

  local parent = fs.dirname(expanded)
  if not parent or parent == "" then
    return nil, "could not determine parent directory"
  end
  if not fs.is_dir(parent) then
    if not opts.allow_missing_parent then
      return nil, "parent directory does not exist: " .. parent
    end
    -- Walk up until we find something that exists.
    local probe = parent
    while probe and probe ~= "/" do
      if fs.exists(probe) then
        if not fs.is_dir(probe) then
          return nil, "path component is not a directory: " .. probe
        end
        break
      end
      probe = fs.dirname(probe)
    end
  end

  if fs.exists(expanded) then
    if not fs.is_dir(expanded) then
      return nil, "destination exists and is not a directory: " .. expanded
    end
    if not fs.is_empty_dir(expanded) then
      return nil, "destination directory is not empty: " .. expanded
    end
  end

  return true, expanded
end

function M.command(argv)
  if type(argv) ~= "table" then
    return nil, "command must be an argv array"
  end
  if #argv == 0 then
    return nil, "command must not be empty"
  end
  for index, value in ipairs(argv) do
    if type(value) ~= "string" then
      return nil, ("command argument %d must be a string"):format(index)
    end
    if value == "" then
      return nil, ("command argument %d must not be empty"):format(index)
    end
    if value:find("%z") then
      return nil, ("command argument %d contains a NUL byte"):format(index)
    end
  end
  return true
end

function M.language_id(id)
  if type(id) ~= "string" or not id:match(constants.LANGUAGE_ID_PATTERN) then
    return nil, "invalid language id: " .. tostring(id)
  end
  return true, id
end

function M.template_id(id)
  if type(id) ~= "string" or not id:match(constants.TEMPLATE_ID_PATTERN) then
    return nil, "invalid template id: " .. tostring(id)
  end
  return true, id
end

local function validate_command_value(value, where)
  if type(value) == "table" and not utils.is_list(value) and value.argv ~= nil then
    local ok, err = M.command(value.argv)
    if not ok then
      return nil, where .. ": " .. err
    end
    if value.cwd ~= nil and type(value.cwd) ~= "string" then
      return nil, where .. ": cwd must be a string"
    end
    return true
  end
  local ok, err = M.command(value)
  if not ok then
    return nil, where .. ": " .. err
  end
  return true
end

-- Validate a declarative project configuration (.forge.json or the return
-- value of an approved .forge.lua).
function M.project_config(config)
  if type(config) ~= "table" then
    return nil, "project configuration must be a table"
  end
  if config.language ~= nil then
    local ok, err = M.language_id(config.language)
    if not ok then
      return nil, err
    end
  end
  for _, field in ipairs({ "runtime", "build_system", "package_manager", "template" }) do
    if config[field] ~= nil and type(config[field]) ~= "string" then
      return nil, ("'%s' must be a string"):format(field)
    end
  end
  if config.options ~= nil and type(config.options) ~= "table" then
    return nil, "'options' must be a table"
  end
  if config.commands ~= nil then
    if type(config.commands) ~= "table" then
      return nil, "'commands' must be a table"
    end
    for kind, value in pairs(config.commands) do
      if type(kind) ~= "string" then
        return nil, "command names must be strings"
      end
      local ok, err = validate_command_value(value, "commands." .. kind)
      if not ok then
        return nil, err
      end
    end
  end
  return true, config
end

return M
