-- C and C++ toolchain profile.

return {
  name = "C/C++",
  languages = { "cpp", "c" },
  groups = {
    {
      name = "Compilers",
      tools = {
        { id = "g++", required = true },
        { id = "clang++" },
        { id = "gcc" },
        { id = "clang" },
      },
    },
    {
      name = "Build tools",
      tools = {
        { id = "cmake" },
        { id = "make", required = true },
        { id = "ninja" },
      },
    },
    {
      name = "Editor and debugging",
      tools = {
        { id = "clangd" },
        { id = "gdb" },
      },
    },
  },
}
