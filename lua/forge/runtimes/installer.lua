-- Distributions and package names.
-- Installation is always explicit: this module only builds a plan and asks
-- for confirmation before handing anything to a terminal.

local fs = require("forge.core.filesystem")
local process = require("forge.core.process")
local utils = require("forge.utils")

local M = {}

local PACKAGES = {
  arch = {
    gcc = "gcc",
    ["g++"] = "gcc",
    clang = "clang",
    ["clang++"] = "clang",
    clangd = "clang",
    make = "make",
    cmake = "cmake",
    ninja = "ninja",
    gdb = "gdb",
    node = "nodejs",
    npm = "npm",
    pnpm = "pnpm",
    yarn = "yarn",
    bun = "bun",
    tsc = "typescript",
    python3 = "python",
    pip = "python-pip",
    pipx = "python-pipx",
    ruff = "ruff",
    basedpyright = "basedpyright",
    pytest = "python-pytest",
    java = "jre-openjdk",
    javac = "jdk-openjdk",
    mvn = "maven",
    gradle = "gradle",
    jdtls = "jdtls",
    git = "git",
  },
  debian = {
    gcc = "gcc",
    ["g++"] = "g++",
    clang = "clang",
    ["clang++"] = "clang",
    clangd = "clangd",
    make = "make",
    cmake = "cmake",
    ninja = "ninja-build",
    gdb = "gdb",
    node = "nodejs",
    npm = "npm",
    pnpm = "pnpm",
    yarn = "yarnpkg",
    bun = nil, -- not in Debian/Ubuntu repositories
    tsc = "node-typescript",
    python3 = "python3",
    pip = "python3-pip",
    pipx = "pipx",
    ruff = "ruff",
    basedpyright = nil, -- npm-installed (npm i -g basedpyright)
    pytest = "python3-pytest",
    java = "default-jre",
    javac = "default-jdk",
    mvn = "maven",
    gradle = "gradle",
    jdtls = "eclipse-jdtls",
    git = "git",
  },
}

local MANUAL_HINTS = {
  bun = "Install Bun from https://bun.sh (curl is not run by Forge).",
  basedpyright = "Install with: npm install -g basedpyright",
  jdtls = "Install from your distribution package or the nvim-jdtls project.",
}

local os_release_cache = nil

function M.os_release()
  if os_release_cache then
    return os_release_cache
  end
  local data = fs.read("/etc/os-release")
  local info = { id = "", like = "", name = "" }
  if data then
    for key, value in data:gmatch("([%w_]+)=\"?([^\n\"]*)\"?") do
      if key == "ID" then
        info.id = value
      elseif key == "ID_LIKE" then
        info.like = value
      elseif key == "NAME" then
        info.name = value
      end
    end
  end
  os_release_cache = info
  return info
end

local function contains_word(haystack, needle)
  for word in tostring(haystack):gmatch("%S+") do
    if word == needle then
      return true
    end
  end
  return false
end

-- Returns "arch", "debian", or nil.
function M.family()
  local info = M.os_release()
  if info.id == "arch" or info.id == "manjaro" or contains_word(info.like, "arch") then
    return "arch"
  end
  if
    info.id == "debian"
    or info.id == "ubuntu"
    or info.id == "pop"
    or info.id == "linuxmint"
    or contains_word(info.like, "debian")
    or contains_word(info.like, "ubuntu")
  then
    return "debian"
  end
  return nil
end

function M.manager()
  local family = M.family()
  if family == "arch" and process.executable("pacman") then
    return "pacman", family
  end
  if family == "debian" and process.executable("apt") then
    return "apt", family
  end
  -- Fall back to whichever manager exists, if the distro is unknown.
  if process.executable("pacman") then
    return "pacman", "arch"
  end
  if process.executable("apt") then
    return "apt", "debian"
  end
  return nil, family
end

function M.package_for(tool, family)
  family = family or M.family()
  if not family then
    return nil
  end
  local packages = PACKAGES[family]
  return packages and packages[tool] or nil
end

-- Build an installation plan without executing anything.
function M.plan(tool)
  if type(tool) ~= "string" or tool == "" then
    return nil, "tool name is required"
  end

  local manager, family = M.manager()
  local plan = {
    tool = tool,
    manager = manager,
    family = family,
    package = nil,
    argv = nil,
    needs_sudo = true,
    installed = process.executable(tool),
    hint = MANUAL_HINTS[tool],
  }

  if plan.installed then
    plan.reason = "already installed"
    return plan
  end

  if not manager then
    plan.reason = "no supported package manager found (Forge supports pacman and apt)"
    return plan
  end

  local package = M.package_for(tool, family)
  plan.package = package
  if not package then
    plan.reason = ("no %s package mapping for '%s'"):format(family, tool)
    return plan
  end

  if manager == "pacman" then
    plan.argv = { "sudo", "pacman", "-S", "--needed", package }
  elseif manager == "apt" then
    plan.argv = { "sudo", "apt", "install", package }
  end
  plan.reason = "ready"
  return plan
end

function M.command_for(tool)
  local plan = M.plan(tool)
  return plan and plan.argv or nil
end

-- Ask for confirmation and start the package manager in a terminal.
-- Never runs AUR helpers, never passes arguments through a shell.
function M.install(tool, opts)
  opts = opts or {}
  local plan, err = M.plan(tool)
  if not plan then
    return nil, err
  end
  if plan.installed then
    utils.notify(("%s is already installed."):format(tool))
    return nil, "already installed"
  end
  if not plan.argv then
    local message = ("Cannot install %s: %s"):format(tool, plan.reason or "unknown reason")
    if plan.hint then
      message = message .. "\n" .. plan.hint
    end
    utils.warn(message)
    return nil, plan.reason
  end

  local select = require("forge.ui.select")
  local prompt = ("Install %s?\n\n  %s\n\n%s")
    :format(tool, utils.display_argv(plan.argv), plan.needs_sudo and "This requires sudo and will ask for your password in the terminal." or "")

  if not select.confirm(prompt, { default = false }) then
    utils.notify("Installation cancelled.")
    return nil, "cancelled"
  end

  local job_id, start_err = process.terminal(plan.argv, {
    label = "install-" .. tool,
    split = opts.split,
  })
  if not job_id then
    utils.error("Could not start installation: " .. tostring(start_err))
    return nil, start_err
  end
  return job_id, plan
end

function M.reset_cache()
  os_release_cache = nil
end

return M
