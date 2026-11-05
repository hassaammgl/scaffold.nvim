-- Python environment discovery.
--
-- Everything here is read-only: it looks for a project root, an existing
-- virtualenv, and interpreter commands. Nothing is created or executed.

local fs = require("scaffold.core.filesystem")

local M = {}

local ROOT_MARKERS = {
  "pyproject.toml",
  "uv.lock",
  ".venv",
  "setup.py",
  "requirements.txt",
  ".git",
}

local function input_dir(path)
  if type(path) ~= "string" or path == "" then
    return vim.uv.cwd()
  end
  local expanded = fs.expand(path)
  local stat = vim.uv.fs_stat(expanded)
  if stat and stat.type == "file" then
    return fs.dirname(expanded)
  end
  return expanded
end

local function is_file(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil and stat.type == "file"
end

function M.find_root(path)
  local dir = input_dir(path)
  return vim.fs.root(dir, ROOT_MARKERS) or vim.uv.cwd()
end

local function venv_at(dir, source)
  if type(dir) ~= "string" or dir == "" then
    return nil
  end
  local python = fs.join(dir, "bin", "python")
  if not is_file(python) then
    return nil
  end
  return { dir = dir, python = python, source = source }
end

function M.find_venv(root)
  if type(root) ~= "string" or root == "" then
    root = vim.uv.cwd()
  end

  local env = vim.env.VIRTUAL_ENV
  if type(env) == "string" and env ~= "" then
    local found = venv_at(fs.expand(env), "VIRTUAL_ENV")
    if found then
      return found
    end
  end

  local found = venv_at(fs.join(root, ".venv"), ".venv")
  if found then
    return found
  end

  return venv_at(fs.join(root, "venv"), "venv")
end

local function system_python()
  local python3 = vim.fn.exepath("python3")
  if python3 ~= "" then
    return python3
  end
  local python = vim.fn.exepath("python")
  if python ~= "" then
    return python
  end
  return nil
end

function M.python(root)
  local venv = M.find_venv(root)
  if venv then
    return venv.python
  end
  return system_python()
end

function M.is_uv_project(root)
  if type(root) ~= "string" or root == "" then
    root = vim.uv.cwd()
  end
  if fs.is_file(fs.join(root, "uv.lock")) then
    return true
  end
  local pyproject = fs.join(root, "pyproject.toml")
  if not fs.is_file(pyproject) then
    return false
  end
  local data = fs.read(pyproject)
  if not data then
    return false
  end
  return data:find("[tool.uv]", 1, true) ~= nil
end

function M.info(path)
  local root = M.find_root(path)
  local venv = M.find_venv(root)
  return {
    root = root,
    venv = venv,
    python = venv and venv.python or system_python(),
    uv = M.is_uv_project(root),
    uv_available = vim.fn.executable("uv") == 1,
  }
end

return M
