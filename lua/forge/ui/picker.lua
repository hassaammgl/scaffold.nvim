-- Project/template pickers built on vim.ui.select.

local registry = require("forge.core.registry")
local fs = require("forge.core.filesystem")
local languages = require("forge.languages")
local templates = require("forge.templates")
local utils = require("forge.utils")
local select = require("forge.ui.select")

local M = {}

function M.project(prompt, opts)
  opts = opts or {}
  local records = opts.records or registry.all()
  if #records == 0 then
    utils.notify("No projects registered yet. Use :ForgeCreate to create one.")
    return nil
  end

  return select.choose(prompt or "Project", records, {
    format_item = function(record)
      local badge = record.language and ("[" .. record.language .. "]") or "[?]"
      local missing = (type(record.path) == "string" and not fs.is_dir(record.path)) and "  (missing)" or ""
      return ("%s  %s  %s%s"):format(utils.truncate(record.name or "?", 28), badge, utils.fmt_path(record.path or ""), missing)
    end,
  })
end

function M.language(prompt)
  languages.load_builtins()
  local list = languages.list()
  if #list == 0 then
    utils.warn("No languages registered.")
    return nil
  end
  return select.choose(prompt or "Language", list, {
    format_item = function(language)
      return ("%s — %s"):format(language.name, language.description or language.id)
    end,
  })
end

function M.template(prompt, language_id)
  templates.load_builtins()
  local list = templates.list(language_id)
  if #list == 0 then
    utils.warn("No templates registered" .. (language_id and (" for " .. language_id) or "") .. ".")
    return nil
  end
  if #list == 1 then
    return list[1]
  end
  return select.choose(prompt or "Template", list, {
    format_item = function(template)
      return ("%s — %s"):format(template.name, template.description or template.id)
    end,
  })
end

function M.tool(prompt, tools)
  local runtimes = require("forge.runtimes")
  tools = tools or runtimes.tool_names()
  return select.choose(prompt or "Tool", tools, {
    format_item = function(tool)
      local definition = runtimes.tools[tool]
      local label = definition and definition.label or tool
      local available = runtimes.is_available(tool)
      return ("%s (%s) — %s"):format(label, tool, available and "installed" or "missing")
    end,
  })
end

return M
