-- Forge.nvim public API and initialization.

local M = {}

M.version = "0.1.0"
M._setup_done = false
M._mapped = {}
M._external_templates_dir = nil

local function apply_keymaps()
  local config = require("forge.config")
  local utils = require("forge.utils")
  local keymaps = config.get("keymaps") or {}
  local commands = {
    dashboard = "Forge",
    create = "ForgeCreate",
    open = "ForgeOpen",
    recent = "ForgeRecent",
    detect = "ForgeDetect",
    build = "ForgeBuild",
    test = "ForgeTest",
    run = "ForgeRun",
    clean = "ForgeClean",
    tools = "ForgeTools",
    doctor = "ForgeDoctor",
    install = "ForgeInstall",
    templates = "ForgeTemplates",
    remove = "ForgeRemove",
    cancel = "ForgeCancel",
  }

  for name, lhs in pairs(keymaps) do
    local command = commands[name]
    if not command then
      utils.warn(("forge.setup: unknown keymap name '%s'"):format(tostring(name)))
    elseif type(lhs) ~= "string" or lhs == "" then
      utils.warn(("forge.setup: keymap '%s' must be a non-empty string"):format(tostring(name)))
    elseif not M._mapped[name] then
      local existing = vim.fn.maparg(lhs, "n")
      if existing ~= "" then
        utils.warn(("forge.setup: '%s' is already mapped; not overriding"):format(lhs))
      else
        vim.keymap.set("n", lhs, "<cmd>" .. command .. "<CR>", {
          desc = "Forge: " .. name,
          silent = true,
        })
        M._mapped[name] = lhs
      end
    end
  end
end

function M.setup(opts)
  local config = require("forge.config")
  local utils = require("forge.utils")
  config.setup(opts)

  require("forge.languages").load_builtins()
  require("forge.templates").load_builtins()
  require("forge.toolchains").load_builtins()
  require("forge.ui").setup()

  local templates_dir = config.get("templates_dir")
  if templates_dir and templates_dir ~= "" and templates_dir ~= M._external_templates_dir then
    local templates = require("forge.templates")
    local loaded, errors = templates.load_external(templates_dir)
    if #loaded > 0 then
      utils.notify(("Forge: loaded %d external template(s)."):format(#loaded))
      M._external_templates_dir = templates_dir
    end
    for _, err in ipairs(errors or {}) do
      utils.warn("Forge template: " .. err)
    end
  end

  apply_keymaps()
  M._setup_done = true
  return M
end

function M._ensure_setup()
  if not M._setup_done then
    M.setup({})
  end
  return M
end

-- Public API ---------------------------------------------------------------

function M.create_project(opts)
  M._ensure_setup()
  if opts == nil then
    return require("forge.ui").create()
  end
  return require("forge.core.project").create(opts)
end

function M.open_project(target)
  M._ensure_setup()
  return require("forge.core.project").open(target)
end

function M.register_language(id, definition)
  return require("forge.languages").register(id, definition)
end

function M.register_template(template)
  return require("forge.templates").register(template)
end

function M.detect_project(path)
  M._ensure_setup()
  return require("forge.core.detector").detect(path)
end

function M.get_current_project()
  M._ensure_setup()
  return require("forge.core.project").current()
end

-- Run a project command kind ("build", "test", "run", "clean") or an explicit
-- argv array. Returns a job id and command spec, or nil and an error.
function M.run_command(command, opts)
  M._ensure_setup()
  opts = opts or {}
  if type(command) == "table" then
    local process = require("forge.core.process")
    local project = require("forge.core.project").current()
    local cwd = opts.cwd or (project and project.path) or vim.uv.cwd()
    return process.terminal(command, {
      cwd = cwd,
      label = opts.label or "command",
      split = opts.split,
    })
  end
  if type(command) == "string" then
    local build = require("forge.managers.build")
    if command == "build" or command == "test" or command == "run" or command == "clean" then
      return build.execute(command, opts)
    end
    return nil, "unknown command kind: " .. command
  end
  return nil, "command must be an argv array or a command kind"
end

function M.projects()
  M._ensure_setup()
  return require("forge.core.registry").all()
end

function M.project(identifier)
  M._ensure_setup()
  return require("forge.core.registry").get(identifier)
end

function M.register_project(project)
  M._ensure_setup()
  return require("forge.core.registry").register(project)
end

function M.unregister_project(identifier)
  M._ensure_setup()
  return require("forge.core.registry").unregister(identifier)
end

function M.recent_projects(limit)
  M._ensure_setup()
  return require("forge.core.registry").recent(limit)
end

function M.search_projects(query)
  M._ensure_setup()
  return require("forge.core.registry").search(query)
end

function M.languages()
  M._ensure_setup()
  return require("forge.languages").list()
end

function M.templates(language)
  M._ensure_setup()
  return require("forge.templates").list(language)
end

function M.refresh_tools()
  M._ensure_setup()
  return require("forge.runtimes").refresh()
end

function M.install_tool(tool)
  M._ensure_setup()
  return require("forge.runtimes.installer").install(tool)
end

function M.cancel_commands()
  return require("forge.core.process").cancel_all()
end

function M.open_dashboard()
  M._ensure_setup()
  return require("forge.ui").dashboard()
end

function M.events()
  return require("forge.core.events")
end

return M
