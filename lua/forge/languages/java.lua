-- Java language definition.

local registry = require("forge.languages.registry")

registry.register("java", {
  name = "Java",
  description = "OpenJDK with Maven, Gradle, or plain javac",
  extensions = { "java" },
  runtimes = { "java", "javac" },
  build_systems = { "maven", "gradle", "javac" },
  package_managers = { "maven", "gradle" },
  templates = { "java-maven", "java-gradle", "java-plain" },
  markers = { "pom.xml", "build.gradle", "build.gradle.kts", "settings.gradle" },
  comment = "//",
})

return true
