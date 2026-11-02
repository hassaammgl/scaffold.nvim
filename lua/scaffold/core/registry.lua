-- Project registry (metadata only).
--
-- The registry is a JSON document with a schema version. Writes are atomic,
-- corrupted files are backed up and recovered as empty, and unregistering
-- NEVER touches project directories.

local config = require("scaffold.config")
local constants = require("scaffold.constants")
local fs = require("scaffold.core.filesystem")
local validator = require("scaffold.core.validator")
local events = require("scaffold.core.events")
local utils = require("scaffold.utils")

local M = {}

M._cache = nil

function M.path()
  return config.get("registry_path")
end

function M.empty()
  return {
    schema_version = constants.SCHEMA_VERSION,
    projects = {},
    order = {},
  }
end

local function backup_corrupt(path)
  local stamp = os.time()
  local backup = ("%s.corrupt-%d"):format(path, stamp)
  local suffix = 0
  while fs.exists(backup) do
    suffix = suffix + 1
    backup = ("%s.corrupt-%d-%d"):format(path, stamp, suffix)
  end
  local data = fs.read(path)
  if data then
    fs.write(backup, data, { overwrite = false, create_dirs = true })
  end
  return backup
end

-- Normalize legacy/array registries and reject future schema versions.
function M.migrate(data)
  if type(data) ~= "table" then
    return nil, "registry must be a JSON object"
  end
  local schema = tonumber(data.schema_version) or 0
  if schema > constants.SCHEMA_VERSION then
    return nil, ("registry schema %d is newer than supported schema %d"):format(schema, constants.SCHEMA_VERSION)
  end

  local projects = {}
  if type(data.projects) == "table" then
    -- Support an array of projects as well as the map form.
    if utils.is_list(data.projects) and #data.projects > 0 then
      for _, record in ipairs(data.projects) do
        if type(record) == "table" and type(record.id) == "string" then
          projects[record.id] = record
        end
      end
    else
      for id, record in pairs(data.projects) do
        if type(id) == "string" and type(record) == "table" then
          record.id = record.id or id
          projects[id] = record
        end
      end
    end
  end

  local order = {}
  local seen = {}
  if type(data.order) == "table" then
    for _, id in ipairs(data.order) do
      if projects[id] and not seen[id] then
        seen[id] = true
        order[#order + 1] = id
      end
    end
  end
  for id in pairs(projects) do
    if not seen[id] then
      order[#order + 1] = id
    end
  end

  return {
    schema_version = constants.SCHEMA_VERSION,
    projects = projects,
    order = order,
  }
end

function M.load(force)
  if M._cache and not force then
    return M._cache
  end

  local path = M.path()
  if not fs.exists(path) then
    M._cache = M.empty()
    return M._cache
  end

  local data, read_err = fs.read(path)
  if not data then
    utils.warn("Scaffold: could not read registry: " .. tostring(read_err))
    M._cache = M.empty()
    return M._cache
  end
  if utils.trim(data) == "" then
    M._cache = M.empty()
    return M._cache
  end

  local decode_ok, decoded = pcall(vim.json.decode, data)
  if not decode_ok then
    local backup = backup_corrupt(path)
    utils.error(("Scaffold: registry is corrupted. A backup was written to %s"):format(backup))
    M._cache = M.empty()
    return M._cache
  end

  local migrated, migrate_err = M.migrate(decoded)
  if not migrated then
    local backup = backup_corrupt(path)
    utils.error(("Scaffold: %s. A backup was written to %s"):format(migrate_err, backup))
    M._cache = M.empty()
    return M._cache
  end

  M._cache = migrated
  return M._cache
end

function M.save(data)
  if type(data) ~= "table" then
    return nil, "registry data must be a table"
  end
  data.schema_version = constants.SCHEMA_VERSION
  local ok, encoded = pcall(vim.json.encode, data)
  if not ok then
    return nil, "could not encode registry: " .. tostring(encoded)
  end
  local written, err = fs.atomic_write(M.path(), encoded .. "\n")
  if not written then
    M._cache = nil
    return nil, err
  end
  M._cache = data
  return true
end

local function normalized(path)
  return fs.normalize(fs.expand(path))
end

function M.find_by_path(path, data)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  data = data or M.load()
  local target = normalized(path)
  for _, record in pairs(data.projects) do
    if type(record.path) == "string" and normalized(record.path) == target then
      return record
    end
  end
  return nil
end

-- Find the registered project whose directory contains `path` (nearest).
function M.find_containing(path, data)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  data = data or M.load()
  local target = normalized(path)
  local best = nil
  for _, record in pairs(data.projects) do
    if type(record.path) == "string" and fs.is_subpath(target, record.path) then
      if not best or #record.path > #best.path then
        best = record
      end
    end
  end
  return best
end

function M.new_id(name, data)
  data = data or M.load()
  local slug = utils.slugify(name or "project")
  local attempt = 0
  while true do
    attempt = attempt + 1
    local id = ("%s-%x%x"):format(slug, os.time(), attempt)
    if not data.projects[id] then
      return id
    end
  end
end

local RECORD_FIELDS = {
  "name",
  "path",
  "language",
  "template",
  "runtime",
  "build_system",
  "package_manager",
  "created_at",
  "last_opened",
  "commands",
  "options",
  "description",
  "source",
}

local function copy_record_fields(source, target)
  for _, field in ipairs(RECORD_FIELDS) do
    if source[field] ~= nil then
      target[field] = vim.deepcopy(source[field])
    end
  end
  return target
end

function M.register(project)
  if type(project) ~= "table" then
    return nil, "project must be a table"
  end
  local name_ok, name_or_err = validator.project_name(project.name)
  if not name_ok then
    return nil, name_or_err
  end
  if type(project.path) ~= "string" or project.path == "" then
    return nil, "project path is required"
  end
  local path = fs.expand(project.path)
  local path_ok, path_err = validator.absolute_path(path)
  if not path_ok then
    return nil, path_err
  end
  if not fs.is_dir(path) then
    return nil, "project path is not a directory: " .. path
  end

  local data = M.load()
  local existing = M.find_by_path(path, data)
  if existing then
    return nil, ("project already registered: %s"):format(path)
  end

  if project.commands ~= nil then
    local commands_ok, commands_err = validator.project_config({ commands = project.commands })
    if not commands_ok then
      return nil, commands_err
    end
  end

  local id = project.id
  if id ~= nil then
    if type(id) ~= "string" or not id:match("^[%w_%-%.]+$") then
      return nil, "invalid project id"
    end
    if data.projects[id] then
      return nil, "project id already exists: " .. id
    end
  else
    id = M.new_id(name_or_err, data)
  end

  local record = {
    id = id,
    name = name_or_err,
    path = path,
    created_at = project.created_at or os.time(),
    last_opened = project.last_opened or 0,
    commands = vim.deepcopy(project.commands or {}),
  }
  copy_record_fields(project, record)
  record.id = id
  record.name = name_or_err
  record.path = path
  record.commands = vim.deepcopy(project.commands or {})

  data.projects[id] = record
  data.order[#data.order + 1] = id

  local saved, save_err = M.save(data)
  if not saved then
    data.projects[id] = nil
    for index = #data.order, 1, -1 do
      if data.order[index] == id then
        table.remove(data.order, index)
      end
    end
    return nil, save_err
  end

  events.emit("project_registered", record)
  return vim.deepcopy(record)
end

local function resolve_record(identifier, data)
  if type(identifier) ~= "string" then
    return nil
  end
  data = data or M.load()
  if data.projects[identifier] then
    return data.projects[identifier]
  end
  return M.find_by_path(identifier, data)
end

function M.get(id)
  if type(id) ~= "string" then
    return nil
  end
  return M.load().projects[id]
end

-- Unregister metadata only. Project files are never deleted.
function M.unregister(identifier)
  local data = M.load()
  local record = resolve_record(identifier, data)
  if not record then
    return nil, "project is not registered: " .. tostring(identifier)
  end

  data.projects[record.id] = nil
  for index = #data.order, 1, -1 do
    if data.order[index] == record.id then
      table.remove(data.order, index)
    end
  end

  local saved, err = M.save(data)
  if not saved then
    return nil, err
  end
  events.emit("project_unregistered", record)
  return vim.deepcopy(record)
end

function M.update(identifier, patch)
  if type(patch) ~= "table" then
    return nil, "patch must be a table"
  end
  local data = M.load()
  local record = resolve_record(identifier, data)
  if not record then
    return nil, "project is not registered: " .. tostring(identifier)
  end

  if patch.name ~= nil then
    local ok, name_or_err = validator.project_name(patch.name)
    if not ok then
      return nil, name_or_err
    end
    record.name = name_or_err
  end
  if patch.commands ~= nil then
    local ok, err = validator.project_config({ commands = patch.commands })
    if not ok then
      return nil, err
    end
    record.commands = vim.deepcopy(patch.commands)
  end
  for _, field in ipairs({
    "language",
    "template",
    "runtime",
    "build_system",
    "package_manager",
    "last_opened",
    "options",
    "description",
  }) do
    if patch[field] ~= nil then
      record[field] = vim.deepcopy(patch[field])
    end
  end

  local saved, err = M.save(data)
  if not saved then
    return nil, err
  end
  events.emit("project_updated", record)
  return vim.deepcopy(record)
end

function M.rename(identifier, new_name)
  return M.update(identifier, { name = new_name })
end

local function sorted_records(data)
  local records = {}
  for _, id in ipairs(data.order) do
    if data.projects[id] then
      records[#records + 1] = data.projects[id]
    end
  end
  -- Include anything that somehow fell out of the order list.
  for id, record in pairs(data.projects) do
    local present = false
    for _, existing in ipairs(records) do
      if existing.id == id then
        present = true
        break
      end
    end
    if not present then
      records[#records + 1] = record
    end
  end
  return records
end

function M.all()
  local records = sorted_records(M.load())
  table.sort(records, function(a, b)
    local left = (a.name or ""):lower()
    local right = (b.name or ""):lower()
    if left == right then
      return (a.path or "") < (b.path or "")
    end
    return left < right
  end)
  return records
end

function M.recent(limit)
  local records = sorted_records(M.load())
  table.sort(records, function(a, b)
    local left = a.last_opened or 0
    local right = b.last_opened or 0
    if left == right then
      return (a.created_at or 0) > (b.created_at or 0)
    end
    return left > right
  end)
  if limit and #records > limit then
    local trimmed = {}
    for index = 1, limit do
      trimmed[index] = records[index]
    end
    return trimmed
  end
  return records
end

function M.search(query)
  query = utils.trim(tostring(query or "")):lower()
  if query == "" then
    return M.all()
  end
  local results = {}
  for _, record in ipairs(M.all()) do
    local haystack = table.concat({
      record.name or "",
      record.path or "",
      record.language or "",
      record.template or "",
    }, " "):lower()
    if haystack:find(query, 1, true) then
      results[#results + 1] = record
    end
  end
  return results
end

function M.touch(identifier)
  local record = resolve_record(identifier, M.load())
  if not record then
    return nil
  end
  record.last_opened = os.time()
  local saved, err = M.save(M.load())
  if not saved then
    return nil, err
  end
  return record
end

-- Returns valid and missing project metadata. No files are touched.
function M.check_paths()
  local data = M.load()
  local valid, missing = {}, {}
  for _, record in ipairs(sorted_records(data)) do
    local exists = type(record.path) == "string" and fs.is_dir(record.path)
    if exists then
      valid[#valid + 1] = record
    else
      local copy = vim.deepcopy(record)
      copy.missing = true
      missing[#missing + 1] = copy
    end
  end
  return valid, missing
end

-- Remove metadata for projects whose directories no longer exist. The caller
-- is responsible for confirming with the user. Files are never deleted.
function M.prune_missing(dry_run)
  local data = M.load()
  local removed = {}
  for id, record in pairs(data.projects) do
    if type(record.path) ~= "string" or not fs.is_dir(record.path) then
      removed[#removed + 1] = vim.deepcopy(record)
      if not dry_run then
        data.projects[id] = nil
        for index = #data.order, 1, -1 do
          if data.order[index] == id then
            table.remove(data.order, index)
          end
        end
      end
    end
  end
  if not dry_run and #removed > 0 then
    local saved, err = M.save(data)
    if not saved then
      return nil, err
    end
  end
  return removed
end

function M.validate()
  local data = M.load()
  local issues = {}
  for _, record in ipairs(sorted_records(data)) do
    if type(record.name) ~= "string" then
      issues[#issues + 1] = "project has no name: " .. tostring(record.id)
    end
    if type(record.path) ~= "string" then
      issues[#issues + 1] = "project has no path: " .. tostring(record.id)
    elseif not fs.is_dir(record.path) then
      issues[#issues + 1] = ("project path is missing: %s"):format(record.path)
    end
  end
  return issues
end

function M.schema_version()
  return M.load().schema_version
end

function M._reset()
  M._cache = nil
end

return M
