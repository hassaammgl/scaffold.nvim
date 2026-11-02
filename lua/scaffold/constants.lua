-- Static constants shared across Scaffold.nvim.
-- This module must not require any other Scaffold module.

local M = {}

M.PLUGIN_NAME = "scaffold"
M.PLUGIN_TITLE = "Scaffold.nvim"
M.SCHEMA_VERSION = 1
M.TEMPLATE_VERSION = 1
M.MAX_PROJECT_NAME = 64
M.MAX_PATH_LENGTH = 4096
M.DEFAULT_REGISTRY_DIR = "scaffold"
M.DEFAULT_PROJECTS_DIRNAME = "Projects"

-- First character must be alphanumeric or underscore. Dots, dashes and
-- further underscores are allowed afterwards, but the name can never start
-- with a dot or a dash, which rules out hidden files and flags.
M.PROJECT_NAME_PATTERN = "^[%w_][%w_%-%._]*$"
M.LANGUAGE_ID_PATTERN = "^[a-z][a-z0-9_%-]*$"
M.TEMPLATE_ID_PATTERN = "^[%w][%w_%-%.]*$"

-- Names that should never become directory names.
M.RESERVED_NAMES = {
  ["."] = true,
  [".."] = true,
  ["con"] = true,
  ["prn"] = true,
  ["aux"] = true,
  ["nul"] = true,
  ["com1"] = true,
  ["com2"] = true,
  ["com3"] = true,
  ["com4"] = true,
  ["lpt1"] = true,
  ["lpt2"] = true,
}

M.COMMAND_NAMES = {
  "Scaffold",
  "ScaffoldCreate",
  "ScaffoldOpen",
  "ScaffoldRecent",
  "ScaffoldDetect",
  "ScaffoldBuild",
  "ScaffoldTest",
  "ScaffoldRun",
  "ScaffoldClean",
  "ScaffoldTools",
  "ScaffoldDoctor",
  "ScaffoldInstall",
  "ScaffoldTemplates",
  "ScaffoldRemove",
  "ScaffoldCancel",
}

return M
