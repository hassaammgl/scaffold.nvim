-- Python toolchain profile.

return {
  name = "Python",
  languages = { "python" },
  groups = {
    {
      name = "Runtime",
      tools = {
        { id = "python3", required = true },
      },
    },
    {
      name = "Packaging",
      tools = {
        { id = "pip", required = true },
        { id = "pipx" },
      },
    },
    {
      name = "Quality and testing",
      tools = {
        { id = "ruff" },
        { id = "basedpyright" },
        { id = "pytest" },
      },
    },
  },
}
