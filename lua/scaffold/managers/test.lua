-- Test command manager.

local build = require("scaffold.managers.build")

local M = {}

function M.resolve(opts)
  return build.resolve(opts and opts.project, "test", opts)
end

function M.execute(opts)
  return build.execute("test", opts)
end

return M
