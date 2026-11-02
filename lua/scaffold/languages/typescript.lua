-- TypeScript language definition.

local registry = require("scaffold.languages.registry")

registry.register("typescript", {
  name = "TypeScript",
  description = "TypeScript on Node.js or Bun",
  extensions = { "ts", "tsx", "mts", "cts" },
  runtimes = { "node", "bun" },
  build_systems = { "npm", "pnpm", "yarn", "bun" },
  package_managers = { "npm", "pnpm", "yarn", "bun" },
  templates = { "ts-node", "ts-bun" },
  markers = { "tsconfig.json", "package.json" },
  comment = "//",
})

return true
