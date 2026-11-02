-- Java toolchain profile.

return {
  name = "Java",
  languages = { "java" },
  groups = {
    {
      name = "Runtime",
      tools = {
        { id = "java", required = true },
        { id = "javac", required = true },
      },
    },
    {
      name = "Build tools",
      tools = {
        { id = "mvn" },
        { id = "gradle" },
      },
    },
    {
      name = "Editor tooling",
      tools = {
        { id = "jdtls" },
      },
    },
  },
}
