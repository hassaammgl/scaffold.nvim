-- Test entrypoint: nvim --headless --clean -u NONE -l tests/run.lua
-- Add the repository root to the runtimepath before loading the plugin.

local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  root .. "/?.lua",
  package.path,
}, ";")

local H = require("tests.harness")

require("tests.validator_spec")
require("tests.filesystem_spec")
require("tests.registry_spec")
require("tests.detector_spec")
require("tests.runtime_spec")
require("tests.template_spec")
require("tests.project_spec")
require("tests.build_spec")
require("tests.extensibility_spec")

H.run()
