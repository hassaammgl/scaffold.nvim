-- Lua language definition.

local registry = require("scaffold.languages.registry")

registry.register("lua", {
  name = "Lua",
  description = "Lua 5.1+ / LuaJIT scripts or Neovim plugins",
  extensions = { "lua" },
  runtimes = { "lua", "luajit" },
  build_systems = { "make" },
  package_managers = { "luarocks" },
  templates = { "lua-cli", "lua-nvim-plugin" },
  markers = { ".luacheckrc", "stylua.toml", ".stylua.toml", ".luarc.json" },
  comment = "--",
})

return true
