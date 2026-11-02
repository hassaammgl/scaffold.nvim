-- Public template API.

local registry = require("scaffold.templates.registry")
local renderer = require("scaffold.templates.renderer")

local M = {}

M.register = registry.register
M.override = registry.override
M.get = registry.get
M.exists = registry.exists
M.list = registry.list
M.ids = registry.ids
M.default_for = registry.default_for
M.validate = registry.validate
M.load_builtins = registry.load_builtins
M.load_external = registry.load_external
M.render = renderer.render_string
M.build_context = renderer.context
M.resolve_command = renderer.resolve_command
M.preview_lines = renderer.preview_lines

function M.reset()
  registry.reset()
end

return M
