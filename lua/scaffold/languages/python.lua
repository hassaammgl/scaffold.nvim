-- Python language definition.

local registry = require("scaffold.languages.registry")

registry.register("python", {
  name = "Python",
  description = "Python 3 with venv and pip",
  extensions = { "py", "pyi" },
  runtimes = { "python3" },
  build_systems = { "pip", "pytest" },
  package_managers = { "pip", "venv" },
  templates = { "python-cli", "python-fastapi", "python-uv" },
  markers = { "pyproject.toml", "requirements.txt", "setup.py", "setup.cfg" },
  comment = "#",
})

return true
