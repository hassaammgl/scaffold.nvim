-- Generic language registry.
--
-- A language definition is a plain table; adding a language never requires
-- touching core code. Definitions are validated at registration time.

local validator = require("forge.core.validator")
local utils = require("forge.utils")

local M = {}

M._languages = {}

local function normalize_list(value, field, id)
  if value == nil then
    return {}
  end
  if type(value) ~= "table" or not utils.is_list(value) then
    return nil, ("language '%s': '%s' must be a list"):format(id, field)
  end
  return value
end

local function validate_definition(id, definition)
  if type(definition) ~= "table" then
    return nil, "language definition must be a table"
  end
  if type(definition.name) ~= "string" or definition.name == "" then
    return nil, ("language '%s': 'name' is required"):format(id)
  end

  for _, field in ipairs({ "extensions", "runtimes", "build_systems", "package_managers", "templates", "markers" }) do
    local list, err = normalize_list(definition[field], field, id)
    if not list then
      return nil, err
    end
    for _, value in ipairs(list) do
      if type(value) ~= "string" or value == "" then
        return nil, ("language '%s': '%s' must contain strings"):format(id, field)
      end
    end
  end

  if definition.comment ~= nil and type(definition.comment) ~= "string" then
    return nil, ("language '%s': 'comment' must be a string"):format(id)
  end
  return true
end

function M.register(id, definition)
  local valid, err = validator.language_id(id)
  if not valid then
    return nil, err
  end
  valid, err = validate_definition(id, definition)
  if not valid then
    return nil, err
  end

  local record = vim.deepcopy(definition)
  record.id = id
  M._languages[id] = record
  return vim.deepcopy(record)
end

function M.unregister(id)
  if M._languages[id] then
    M._languages[id] = nil
    return true
  end
  return false
end

function M.get(id)
  if type(id) ~= "string" then
    return nil
  end
  return M._languages[id]
end

function M.exists(id)
  return M.get(id) ~= nil
end

function M.ids()
  local ids = {}
  for id in pairs(M._languages) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  return ids
end

function M.list()
  local languages = {}
  for _, id in ipairs(M.ids()) do
    languages[#languages + 1] = M._languages[id]
  end
  return languages
end

-- Find a language by file extension or filename (e.g. "main.cpp").
function M.by_extension(filename)
  if type(filename) ~= "string" then
    return nil
  end
  local base = vim.fs.basename(filename):lower()
  local extension = base:match("%.([%w_]+)$")
  if extension then
    for _, language in ipairs(M.list()) do
      for _, candidate in ipairs(language.extensions or {}) do
        if candidate:lower() == extension then
          return language
        end
      end
    end
  end
  -- Exact marker filenames such as "CMakeLists.txt" or "Makefile".
  for _, language in ipairs(M.list()) do
    for _, marker in ipairs(language.markers or {}) do
      if marker == base then
        return language
      end
    end
  end
  return nil
end

function M.default_template(id)
  local language = M.get(id)
  if language and language.templates and language.templates[1] then
    return language.templates[1]
  end
  return nil
end

function M.reset()
  M._languages = {}
end

return M
