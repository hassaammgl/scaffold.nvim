-- Restricted Lua loader for user/project configuration files.
--
-- Files loaded here can build tables and strings, but have no access to io,
-- os, package, require, or vim. This makes accidental (or malicious) project
-- configuration unable to touch the system directly. Loading still requires
-- explicit approval at the call site.

local fs = require("forge.core.filesystem")

local M = {}

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
    rawget = rawget,
    rawset = rawset,
  }
end

function M.load_file(path, label)
  label = label or "Lua file"
  if type(path) ~= "string" or path == "" then
    return nil, "invalid path"
  end
  if not fs.is_file(path) then
    return nil, "file does not exist: " .. path
  end

  local chunk, load_err
  if setfenv then
    chunk, load_err = loadfile(path)
    if chunk then
      setfenv(chunk, restricted_env())
    end
  else
    local data, read_err = fs.read(path)
    if not data then
      return nil, read_err
    end
    chunk, load_err = load(data, "@" .. path, "t", restricted_env())
  end

  if not chunk then
    return nil, ("%s could not be loaded: %s"):format(label, tostring(load_err))
  end

  local ok, result = pcall(chunk)
  if not ok then
    return nil, ("%s failed: %s"):format(label, tostring(result))
  end
  if type(result) ~= "table" then
    return nil, label .. " must return a table"
  end
  return result
end

return M
