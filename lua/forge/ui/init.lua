-- Lazy UI facade.

local M = {}

local function lazy(module, method)
  return function(...)
    local loaded = require(module)
    return loaded[method](...)
  end
end

M.dashboard = lazy("forge.ui.dashboard", "open")
M.create = lazy("forge.ui.wizard", "create")
M.runtimes = lazy("forge.ui.screens", "runtimes")
M.toolchains = lazy("forge.ui.screens", "toolchains")
M.templates = lazy("forge.ui.screens", "templates")
M.browse_templates = lazy("forge.ui.screens", "browse_templates")
M.settings = lazy("forge.ui.screens", "settings")
M.detect = lazy("forge.ui.screens", "detect")
M.project_info = lazy("forge.ui.screens", "project_info")
M.dependencies = lazy("forge.ui.screens", "dependencies")
M.install = lazy("forge.ui.screens", "install")
M.doctor = lazy("forge.ui.screens", "doctor")
M.jobs = lazy("forge.ui.screens", "jobs")

function M.setup()
  require("forge.ui.window").ensure_highlights()
end

return M
