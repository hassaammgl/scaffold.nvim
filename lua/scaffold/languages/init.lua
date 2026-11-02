-- Public language API + built-in loading.

local registry = require("scaffold.languages.registry")
local utils = require("scaffold.utils")

local M = {}

local BUILTINS = {
  "scaffold.languages.c",
  "scaffold.languages.cpp",
  "scaffold.languages.javascript",
  "scaffold.languages.typescript",
  "scaffold.languages.bun",
  "scaffold.languages.python",
  "scaffold.languages.java",
  "scaffold.languages.lua",
}

M._builtins_loaded = false

function M.load_builtins()
  if M._builtins_loaded then
    return
  end
  for _, module in ipairs(BUILTINS) do
    local ok, err = pcall(require, module)
    if not ok then
      utils.warn(("Scaffold: could not load language module %s: %s"):format(module, tostring(err)))
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
