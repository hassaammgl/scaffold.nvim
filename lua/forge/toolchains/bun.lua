-- Bun toolchain profile.

return {
  name = "Bun",
  languages = { "bun" },
  groups = {
    {
      name = "Runtime",
      tools = {
        { id = "bun", required = true },
      },
    },
    {
      name = "Bun tooling",
      tools = {
        { id = "tsc" },
        { id = "node" },
      },
    },
  },
}
