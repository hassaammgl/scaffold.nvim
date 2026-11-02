-- Lazy UI facade.

local M = {}

local function lazy(module, method)
  return function(...)
    local loaded = require(module)
    return loaded[method](...)
  end
end

M.dashboard = lazy("scaffold.ui.dashboard", "open")
M.create = lazy("scaffold.ui.wizard", "create")
M.runtimes = lazy("scaffold.ui.screens", "runtimes")
M.toolchains = lazy("scaffold.ui.screens", "toolchains")
M.templates = lazy("scaffold.ui.screens", "templates")
M.browse_templates = lazy("scaffold.ui.screens", "browse_templates")
M.settings = lazy("scaffold.ui.screens", "settings")
M.detect = lazy("scaffold.ui.screens", "detect")
M.project_info = lazy("scaffold.ui.screens", "project_info")
M.dependencies = lazy("scaffold.ui.screens", "dependencies")
M.install = lazy("scaffold.ui.screens", "install")
M.doctor = lazy("scaffold.ui.screens", "doctor")
M.jobs = lazy("scaffold.ui.screens", "jobs")

function M.setup()
  require("scaffold.ui.window").ensure_highlights()
end

return M
