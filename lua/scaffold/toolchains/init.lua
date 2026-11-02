-- Toolchain profile registry. Profiles describe tools; they never start
-- language servers or install anything.

local runtimes = require("scaffold.runtimes")
local utils = require("scaffold.utils")

local M = {}

local BUILTIN_MODULES = {
  "scaffold.toolchains.cpp",
  "scaffold.toolchains.node",
  "scaffold.toolchains.bun",
  "scaffold.toolchains.python",
  "scaffold.toolchains.java",
}

M._profiles = {}
M._builtins_loaded = false

function M.register(profile)
  if type(profile) ~= "table" or type(profile.languages) ~= "table" then
    return nil, "toolchain profile requires a languages list"
  end
  for _, language in ipairs(profile.languages) do
    M._profiles[language] = profile
  end
  return profile
end

function M.get(language)
  return M._profiles[language]
end

function M.load_builtins()
  if M._builtins_loaded then
    return
  end
  for _, module_name in ipairs(BUILTIN_MODULES) do
    local ok, profile = pcall(require, module_name)
    if not ok then
      utils.warn(("Scaffold: could not load toolchain profile %s: %s"):format(module_name, tostring(profile)))
    else
      local registered, err = M.register(profile)
      if not registered then
        utils.warn(("Scaffold: invalid toolchain profile %s: %s"):format(module_name, tostring(err)))
      end
    end
  end
  M._builtins_loaded = true
end

-- opts is forwarded to the runtime detector (refresh, version, timeout).
function M.status(language, opts)
  local profile = M.get(language)
  if not profile then
    return nil, "no toolchain profile for language: " .. tostring(language)
  end

  local groups = {}
  for _, group in ipairs(profile.groups or {}) do
    local tools = {}
    for _, entry in ipairs(group.tools or {}) do
      local id = type(entry) == "table" and entry.id or entry
      local required = type(entry) == "table" and entry.required or false
      local info = runtimes.info(id, opts)
      tools[#tools + 1] = {
        id = id,
        label = info and info.label or id,
        found = info and info.found or false,
        version = info and info.version or nil,
        path = info and info.path or nil,
        required = required,
      }
    end
    groups[#groups + 1] = { name = group.name, tools = tools }
  end

  return {
    language = language,
    name = profile.name,
    groups = groups,
  }
end

function M.report(opts)
  local seen = {}
  local report = {}
  for _, language in ipairs({ "cpp", "javascript", "typescript", "bun", "python", "java" }) do
    local profile = M.get(language)
    if profile and not seen[profile] then
      seen[profile] = true
      local status = M.status(language, opts)
      if status then
        report[#report + 1] = status
      end
    end
  end
  return report
end

function M.reset()
  M._profiles = {}
  M._builtins_loaded = false
end

return M
