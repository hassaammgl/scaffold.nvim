-- Template registry, validation, and external template loading.

local languages = require("scaffold.languages")
local fs = require("scaffold.core.filesystem")
local validator = require("scaffold.core.validator")
local utils = require("scaffold.utils")

local M = {}

M._templates = {}
M._builtins_loaded = false

local BUILTIN_MODULES = {
  "scaffold.templates.cpp",
  "scaffold.templates.c",
  "scaffold.templates.javascript",
  "scaffold.templates.typescript",
  "scaffold.templates.bun",
  "scaffold.templates.python",
  "scaffold.templates.java",
}

local function is_string_map(value)
  if type(value) ~= "table" then
    return false
  end
  for key in pairs(value) do
    if type(key) ~= "string" then
      return false
    end
  end
  return true
end

function M.validate(template)
  local errors = {}
  if type(template) ~= "table" then
    return { "template must be a table" }
  end
  local ok, err = validator.template_id(template.id)
  if not ok then
    errors[#errors + 1] = err
  end
  if type(template.name) ~= "string" or template.name == "" then
    errors[#errors + 1] = "template name is required"
  end
  if type(template.language) ~= "string" or template.language == "" then
    errors[#errors + 1] = "template language is required"
  elseif not languages.exists(template.language) then
    errors[#errors + 1] = ("unknown language '%s'; register the language first"):format(template.language)
  end
  if template.version ~= nil and type(template.version) ~= "number" then
    errors[#errors + 1] = "template version must be a number"
  end

  if not is_string_map(template.files) then
    errors[#errors + 1] = "template files must be a table of path -> content"
  else
    local count = 0
    for path, content in pairs(template.files) do
      count = count + 1
      local path_ok, path_err = validator.relative_path(path)
      if not path_ok then
        errors[#errors + 1] = ("invalid file path '%s': %s"):format(path, path_err)
      end
      if type(content) ~= "string" and type(content) ~= "function" then
        errors[#errors + 1] = ("file '%s' must be a string or function"):format(path)
      end
    end
    if count == 0 then
      errors[#errors + 1] = "template must contain at least one file"
    end
  end

  if template.options ~= nil then
    if type(template.options) ~= "table" then
      errors[#errors + 1] = "template options must be a table"
    else
      for name, definition in pairs(template.options) do
        if type(name) ~= "string" then
          errors[#errors + 1] = "option names must be strings"
        elseif type(definition) ~= "table" then
          errors[#errors + 1] = ("option '%s' must be a table"):format(name)
        else
          local option_type = definition.type or "input"
          if option_type == "select" then
            if type(definition.values) ~= "table" or #definition.values == 0 then
              errors[#errors + 1] = ("option '%s' requires a non-empty values list"):format(name)
            elseif definition.default ~= nil and not utils.tbl_contains(definition.values, definition.default) then
              errors[#errors + 1] = ("option '%s' default must be one of its values"):format(name)
            end
          elseif option_type == "confirm" then
            if definition.default ~= nil and type(definition.default) ~= "boolean" then
              errors[#errors + 1] = ("option '%s' default must be a boolean"):format(name)
            end
          elseif option_type ~= "input" then
            errors[#errors + 1] = ("option '%s' has unknown type '%s'"):format(name, tostring(option_type))
          end
        end
      end
    end
  end

  if template.commands ~= nil then
    if type(template.commands) ~= "table" then
      errors[#errors + 1] = "template commands must be a table"
    else
      for kind, value in pairs(template.commands) do
        if type(kind) ~= "string" then
          errors[#errors + 1] = "command kinds must be strings"
        elseif type(value) ~= "function" then
          if type(value) ~= "table" then
            errors[#errors + 1] = ("command '%s' must be a function or argv array"):format(kind)
          elseif not utils.is_list(value) then
            if value.argv == nil then
              errors[#errors + 1] = ("command '%s' must be an argv array or {argv=...}"):format(kind)
            else
              local argv_ok, argv_err = validator.command(value.argv)
              if not argv_ok then
                errors[#errors + 1] = ("command '%s': %s"):format(kind, argv_err)
              end
            end
          else
            local argv_ok, argv_err = validator.command(value)
            if not argv_ok then
              errors[#errors + 1] = ("command '%s': %s"):format(kind, argv_err)
            end
          end
        end
      end
    end
  end

  for _, field in ipairs({ "build_systems", "package_managers", "runtime_options", "requires" }) do
    if template[field] ~= nil then
      if type(template[field]) ~= "table" or not utils.is_list(template[field]) then
        errors[#errors + 1] = ("template '%s' must be a list"):format(field)
      else
        for _, value in ipairs(template[field]) do
          if type(value) ~= "string" then
            errors[#errors + 1] = ("template '%s' must contain strings"):format(field)
          end
        end
      end
    end
  end

  return errors
end

function M.register(template)
  local errors = M.validate(template)
  if #errors > 0 then
    return nil, table.concat(errors, "; ")
  end
  if M._templates[template.id] then
    return nil, ("template '%s' is already registered"):format(template.id)
  end

  local record = vim.deepcopy(template)
  record.version = record.version or 1
  M._templates[record.id] = record
  return record
end

-- Register or replace a template. Intended for the public extension API.
function M.override(template)
  local errors = M.validate(template)
  if #errors > 0 then
    return nil, table.concat(errors, "; ")
  end
  local record = vim.deepcopy(template)
  record.version = record.version or 1
  M._templates[record.id] = record
  return record
end

function M.get(id)
  if type(id) ~= "string" then
    return nil
  end
  return M._templates[id]
end

function M.exists(id)
  return M.get(id) ~= nil
end

function M.ids()
  local ids = {}
  for id in pairs(M._templates) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  return ids
end

function M.list(language)
  local templates = {}
  for _, id in ipairs(M.ids()) do
    local template = M._templates[id]
    if not language or template.language == language then
      templates[#templates + 1] = template
    end
  end
  return templates
end

function M.default_for(language)
  local language_def = languages.get(language)
  if language_def then
    for _, id in ipairs(language_def.templates or {}) do
      if M._templates[id] then
        return M._templates[id]
      end
    end
  end
  local available = M.list(language)
  return available[1]
end

function M.load_builtins()
  if M._builtins_loaded then
    return
  end
  languages.load_builtins()
  for _, module_name in ipairs(BUILTIN_MODULES) do
    local ok, module = pcall(require, module_name)
    if not ok then
      utils.warn(("Scaffold: could not load template module %s: %s"):format(module_name, tostring(module)))
    else
      local templates = module and module.templates or {}
      for _, template in ipairs(templates) do
        local record, err = M.register(template)
        if not record then
          utils.warn(("Scaffold: invalid built-in template: %s"):format(err))
        end
      end
    end
  end
  M._builtins_loaded = true
end

local function restricted_env()
  return {
    string = string,
    table = table,
    math = math,
    pairs = pairs,
    ipairs = ipairs,
    next = next,
    select = select,
    type = type,
    tostring = tostring,
    tonumber = tonumber,
    unpack = unpack,
    error = error,
    assert = assert,
    pcall = pcall,
  }
end

local function normalize_external(result)
  if type(result) ~= "table" then
    return {}
  end
  if result.templates then
    return result.templates
  end
  if result.id and result.files then
    return { result }
  end
  return result
end

-- Load trusted, user-provided template modules from a directory. Files are
-- executed in a restricted environment and are never loaded from projects.
function M.load_external(directory)
  local loaded, errors = {}, {}
  if not directory or directory == "" then
    return loaded, errors
  end
  directory = fs.expand(directory)
  if not fs.is_dir(directory) then
    return loaded, { "templates directory does not exist: " .. directory }
  end

  local found = vim.fs.find(function(name)
    return name:match("%.lua$") ~= nil
  end, { path = directory, type = "file", limit = 500 })
  table.sort(found)

  for _, file in ipairs(found) do
    local chunk, load_err
    if setfenv then
      chunk, load_err = loadfile(file)
      if chunk then
        setfenv(chunk, restricted_env())
      end
    else
      local data = fs.read(file)
      if data then
        chunk, load_err = load(data, "@" .. file, "t", restricted_env())
      else
        load_err = "could not read file"
      end
    end

    if not chunk then
      errors[#errors + 1] = ("%s: %s"):format(file, tostring(load_err))
    else
      local ok, result = pcall(chunk)
      if not ok then
        errors[#errors + 1] = ("%s: %s"):format(file, tostring(result))
      else
        for _, template in ipairs(normalize_external(result)) do
          local record, err = M.register(template)
          if record then
            loaded[#loaded + 1] = record.id
          else
            errors[#errors + 1] = ("%s: %s"):format(file, err)
          end
        end
      end
    end
  end

  return loaded, errors
end

function M.reset()
  M._templates = {}
  M._builtins_loaded = false
end

return M
