-- Node/TypeScript toolchain profile.

return {
  name = "Node.js / TypeScript",
  languages = { "javascript", "typescript" },
  groups = {
    {
      name = "Runtime",
      tools = {
        { id = "node", required = true },
        { id = "bun" },
      },
    },
    {
      name = "Package managers",
      tools = {
        { id = "npm" },
        { id = "pnpm" },
        { id = "yarn" },
        { id = "bun" },
      },
    },
    {
      name = "Tooling",
      tools = {
        { id = "tsc" },
      },
    },
  },
}
