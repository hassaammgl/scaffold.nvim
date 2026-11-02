-- C language definition.

local registry = require("forge.languages.registry")

registry.register("c", {
  name = "C",
  description = "C17/C23 with GCC or Clang",
  extensions = { "c", "h" },
  runtimes = { "gcc", "clang" },
  build_systems = { "cmake", "make", "ninja" },
  package_managers = {},
  templates = { "c-cmake", "c-make" },
  markers = { "CMakeLists.txt", "compile_commands.json", "Makefile" },
  comment = "//",
})

return true
