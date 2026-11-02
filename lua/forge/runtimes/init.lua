-- Public runtime API.

local detector = require("forge.runtimes.detector")
local installer = require("forge.runtimes.installer")
local version = require("forge.runtimes.version")

local M = {}

M.info = detector.info
M.detect = detector.detect
M.refresh = detector.refresh
M.installed = detector.installed
M.is_available = detector.is_available
M.tool_names = detector.tool_names
M.define = detector.define
M.clear_cache = detector.clear_cache
M.plan_install = installer.plan
M.install = installer.install
M.family = installer.family
M.manager = installer.manager
M.tools = detector.TOOLS
M.version = version

return M
