-- Lua toolchain profile.

return {
  name = "Lua",
  languages = { "lua" },
  groups = {
    {
      name = "Runtime",
      tools = {
        { id = "lua", required = true },
        { id = "luajit" },
      },
    },
    {
      name = "Packaging",
      tools = {
        { id = "luarocks" },
      },
    },
    {
      name = "Quality and testing",
      tools = {
        { id = "stylua" },
        { id = "luacheck" },
        { id = "busted" },
      },
    },
  },
}
