-- Environment overview: runtimes and toolchains, on demand only.

local runtimes = require("scaffold.runtimes")
local toolchains = require("scaffold.toolchains")

local M = {}

function M.runtimes(opts)
  return runtimes.detect(runtimes.tool_names(), opts)
end

function M.toolchain(language, opts)
  return toolchains.status(language, opts)
end

function M.toolchains(opts)
  return toolchains.report(opts)
end

function M.overview(opts)
  return {
    runtimes = M.runtimes(opts),
    toolchains = M.toolchains(opts),
  }
end

return M
