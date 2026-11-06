-- Scaffold.nvim public API and initialization.

local M = {}

M.version = "0.1.0"
M._setup_done = false
M._mapped = {}
M._external_templates_dir = nil

local function apply_keymaps()
  local config = require("scaffold.config")
  local utils = require("scaffold.utils")
  local keymaps = config.get("keymaps") or {}
  local commands = {
    dashboard = "Scaffold",
    create = "ScaffoldCreate",
    open = "ScaffoldOpen",
    recent = "ScaffoldRecent",
    detect = "ScaffoldDetect",
    build = "ScaffoldBuild",
    test = "ScaffoldTest",
    run = "ScaffoldRun",
    clean = "ScaffoldClean",
    tools = "ScaffoldTools",
    doctor = "ScaffoldDoctor",
    install = "ScaffoldInstall",
    templates = "ScaffoldTemplates",
    remove = "ScaffoldRemove",
    cancel = "ScaffoldCancel",
  }

  for name, lhs in pairs(keymaps) do
    local command = commands[name]
    if not command then
      utils.warn(("scaffold.setup: unknown keymap name '%s'"):format(tostring(name)))
    elseif type(lhs) ~= "string" or lhs == "" then
      utils.warn(("scaffold.setup: keymap '%s' must be a non-empty string"):format(tostring(name)))
    elseif not M._mapped[name] then
      local existing = vim.fn.maparg(lhs, "n")
      if existing ~= "" then
        utils.warn(("scaffold.setup: '%s' is already mapped; not overriding"):format(lhs))
      else
        vim.keymap.set("n", lhs, "<cmd>" .. command .. "<CR>", {
          desc = "Scaffold: " .. name,
          silent = true,
        })
        M._mapped[name] = lhs
      end
    end
  end
end

function M.setup(opts)
  local config = require("scaffold.config")
  local utils = require("scaffold.utils")
  config.setup(opts)

  require("scaffold.languages").load_builtins()
  require("scaffold.templates").load_builtins()
  require("scaffold.toolchains").load_builtins()
  require("scaffold.ui").setup()

  local templates_dir = config.get("templates_dir")
  if templates_dir and templates_dir ~= "" and templates_dir ~= M._external_templates_dir then
    local templates = require("scaffold.templates")
    local loaded, errors = templates.load_external(templates_dir)
    if #loaded > 0 then
      utils.notify(("Scaffold: loaded %d external template(s)."):format(#loaded))
      M._external_templates_dir = templates_dir
    end
    for _, err in ipairs(errors or {}) do
      utils.warn("Scaffold template: " .. err)
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
    return require("scaffold.ui").create()
  end
  return require("scaffold.core.project").create(opts)
end

function M.open_project(target)
  M._ensure_setup()
  return require("scaffold.core.project").open(target)
end

function M.register_language(id, definition)
  return require("scaffold.languages").register(id, definition)
end

function M.register_template(template)
  return require("scaffold.templates").register(template)
end

function M.detect_project(path)
  M._ensure_setup()
  return require("scaffold.core.detector").detect(path)
end

function M.get_current_project()
  M._ensure_setup()
  return require("scaffold.core.project").current()
end

-- Run a project command kind ("build", "test", "run", "clean") or an explicit
-- argv array. Returns a job id and command spec, or nil and an error.
function M.run_command(command, opts)
  M._ensure_setup()
  opts = opts or {}
  if type(command) == "table" then
    local process = require("scaffold.core.process")
    local project = require("scaffold.core.project").current()
    local cwd = opts.cwd or (project and project.path) or vim.uv.cwd()
    return process.terminal(command, {
      cwd = cwd,
      label = opts.label or "command",
      split = opts.split,
    })
  end
  if type(command) == "string" then
    local build = require("scaffold.managers.build")
    if command == "build" or command == "test" or command == "run" or command == "clean" then
      return build.execute(command, opts)
    end
    return nil, "unknown command kind: " .. command
  end
  return nil, "command must be an argv array or a command kind"
end

function M.projects()
  M._ensure_setup()
  return require("scaffold.core.registry").all()
end

function M.project(identifier)
  M._ensure_setup()
  return require("scaffold.core.registry").get(identifier)
end

function M.register_project(project)
  M._ensure_setup()
  return require("scaffold.core.registry").register(project)
end

function M.unregister_project(identifier)
  M._ensure_setup()
  return require("scaffold.core.registry").unregister(identifier)
end

function M.recent_projects(limit)
  M._ensure_setup()
  return require("scaffold.core.registry").recent(limit)
end

function M.search_projects(query)
  M._ensure_setup()
  return require("scaffold.core.registry").search(query)
end

function M.languages()
  M._ensure_setup()
  return require("scaffold.languages").list()
end

function M.templates(language)
  M._ensure_setup()
  return require("scaffold.templates").list(language)
end

function M.refresh_tools()
  M._ensure_setup()
  return require("scaffold.runtimes").refresh()
end

function M.install_tool(tool)
  M._ensure_setup()
  return require("scaffold.runtimes.installer").install(tool)
end

function M.cancel_commands()
  return require("scaffold.core.process").cancel_all()
end

function M.open_dashboard()
  M._ensure_setup()
  return require("scaffold.ui").dashboard()
end

function M.events()
  return require("scaffold.core.events")
end

-- Python environment helpers ------------------------------------------------

function M.python_env(path)
  return require("scaffold.core.python_env").info(path)
end

function M.python_path(path)
  local env = require("scaffold.core.python_env")
  return env.python(env.find_root(path))
end

-- Add an import root to a settings namespace (python or basedpyright) without
-- duplicating an entry the user already configured.
local function add_extra_path(settings, namespace, path)
  local ns = settings[namespace]
  if type(ns) ~= "table" then
    ns = {}
    settings[namespace] = ns
  end
  local analysis = ns.analysis
  if type(analysis) ~= "table" then
    analysis = {}
    ns.analysis = analysis
  end
  local extra = analysis.extraPaths
  if type(extra) ~= "table" then
    extra = {}
    analysis.extraPaths = extra
  end
  for _, value in ipairs(extra) do
    if value == path then
      return
    end
  end
  extra[#extra + 1] = path
end

-- Opt-in LSP hook: use the project virtualenv for Pyright-like servers.
-- Scaffold never starts or configures an LSP client on its own.
function M.python_lsp_before_init(_, config)
  local env = require("scaffold.core.python_env")
  local root = config and config.root_dir or vim.uv.cwd()
  local project_root = env.find_root(root)
  config.settings = config.settings or {}

  local python = env.python(project_root)
  if python then
    if type(config.settings.python) ~= "table" then
      config.settings.python = {}
    end
    config.settings.python.pythonPath = python
  end

  -- src-layout projects keep importable packages under <root>/src. Add it as
  -- an import root so `src/pkg/module.py` resolves from other files too.
  local src = vim.fs.joinpath(project_root, "src")
  local stat = vim.uv.fs_stat(src)
  if stat and stat.type == "directory" then
    add_extra_path(config.settings, "python", src)
    add_extra_path(config.settings, "basedpyright", src)
  end
end

return M
