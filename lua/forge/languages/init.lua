-- Public language API + built-in loading.

local registry = require("forge.languages.registry")
local utils = require("forge.utils")

local M = {}

local BUILTINS = {
  "forge.languages.c",
  "forge.languages.cpp",
  "forge.languages.javascript",
  "forge.languages.typescript",
  "forge.languages.bun",
  "forge.languages.python",
  "forge.languages.java",
}

M._builtins_loaded = false

function M.load_builtins()
  if M._builtins_loaded then
    return
  end
  for _, module in ipairs(BUILTINS) do
    local ok, err = pcall(require, module)
    if not ok then
      utils.warn(("Forge: could not load language module %s: %s"):format(module, tostring(err)))
    end
  end
  M._builtins_loaded = true
end

M.register = registry.register
M.unregister = registry.unregister
M.get = registry.get
M.exists = registry.exists
M.list = registry.list
M.ids = registry.ids
M.by_extension = registry.by_extension
M.default_template = registry.default_template

function M.reset()
  registry.reset()
  M._builtins_loaded = false
end

return M
