-- C++ language definition.

local registry = require("scaffold.languages.registry")

registry.register("cpp", {
  name = "C++",
  description = "C++17/20/23/26 with GCC or Clang",
  extensions = { "cpp", "cc", "cxx", "hpp", "hh", "hxx", "ipp", "tpp" },
  runtimes = { "g++", "clang++" },
  build_systems = { "cmake", "make", "ninja" },
  package_managers = {},
  templates = { "cpp-cmake", "cpp-make" },
  markers = { "CMakeLists.txt", "compile_commands.json", "Makefile" },
  comment = "//",
})

return true
