-- JavaScript language definition.

local registry = require("forge.languages.registry")

registry.register("javascript", {
  name = "JavaScript",
  description = "Node.js or Bun projects",
  extensions = { "js", "mjs", "cjs", "jsx" },
  runtimes = { "node", "bun" },
  build_systems = { "npm", "pnpm", "yarn", "bun" },
  package_managers = { "npm", "pnpm", "yarn", "bun" },
  templates = { "js-vanilla", "js-express" },
  markers = { "package.json", "jsconfig.json" },
  comment = "//",
})

return true
