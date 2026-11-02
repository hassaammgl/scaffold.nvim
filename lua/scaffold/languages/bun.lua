-- Bun language definition.

local registry = require("scaffold.languages.registry")

registry.register("bun", {
  name = "Bun",
  description = "Bun runtime, package manager, and test runner",
  extensions = { "ts", "tsx", "js", "jsx" },
  runtimes = { "bun" },
  build_systems = { "bun" },
  package_managers = { "bun" },
  templates = { "bun-ts" },
  markers = { "bun.lock", "bun.lockb", "bunfig.toml" },
  comment = "//",
})

return true
