-- Runtime and tool detection.
--
-- Detection is explicit: it runs only when called by a user action (or by a
-- UI screen the user opened). Results are cached in memory with a TTL from
-- the configuration. Nothing here starts language servers.

local process = require("scaffold.core.process")
local version = require("scaffold.runtimes.version")
local config = require("scaffold.config")
local utils = require("scaffold.utils")

local M = {}

-- Each tool: display label, command, version args, optional fallbacks
-- (alternate argv arrays, tried in order), and category.
M.TOOLS = {
  gcc = { label = "GCC", cmd = "gcc", args = { "--version" }, category = "c" },
  ["g++"] = { label = "G++", cmd = "g++", args = { "--version" }, category = "c" },
  clang = { label = "Clang", cmd = "clang", args = { "--version" }, category = "c" },
  ["clang++"] = { label = "Clang++", cmd = "clang++", args = { "--version" }, category = "c" },
  clangd = { label = "clangd", cmd = "clangd", args = { "--version" }, category = "c" },
  make = { label = "Make", cmd = "make", args = { "--version" }, category = "c" },
  cmake = { label = "CMake", cmd = "cmake", args = { "--version" }, category = "c" },
  ninja = { label = "Ninja", cmd = "ninja", args = { "--version" }, category = "c" },
  gdb = { label = "GDB", cmd = "gdb", args = { "--version" }, category = "c" },

  node = { label = "Node.js", cmd = "node", args = { "--version" }, category = "js" },
  npm = { label = "npm", cmd = "npm", args = { "--version" }, category = "js" },
  pnpm = { label = "pnpm", cmd = "pnpm", args = { "--version" }, category = "js" },
  yarn = { label = "Yarn", cmd = "yarn", args = { "--version" }, category = "js" },
  bun = { label = "Bun", cmd = "bun", args = { "--version" }, category = "js" },
  tsc = { label = "TypeScript", cmd = "tsc", args = { "--version" }, category = "js" },

  python3 = {
    label = "Python",
    cmd = "python3",
    args = { "--version" },
    fallbacks = { { "python", "--version" } },
    category = "python",
  },
  pip = {
    label = "pip",
    cmd = "pip",
    args = { "--version" },
    fallbacks = { { "pip3", "--version" }, { "python3", "-m", "pip", "--version" } },
    category = "python",
  },
  pipx = { label = "pipx", cmd = "pipx", args = { "--version" }, category = "python" },
  ruff = { label = "Ruff", cmd = "ruff", args = { "--version" }, category = "python" },
  basedpyright = { label = "basedpyright", cmd = "basedpyright", args = { "--version" }, category = "python" },
  pytest = {
    label = "pytest",
    cmd = "pytest",
    args = { "--version" },
    fallbacks = { { "python3", "-m", "pytest", "--version" } },
    category = "python",
  },

  java = { label = "OpenJDK", cmd = "java", args = { "--version" }, category = "java" },
  javac = { label = "javac", cmd = "javac", args = { "--version" }, category = "java" },
  mvn = { label = "Maven", cmd = "mvn", args = { "--version" }, category = "java" },
  gradle = { label = "Gradle", cmd = "gradle", args = { "--version" }, category = "java" },
  jdtls = { label = "JDTLS", cmd = "jdtls", args = { "--version" }, category = "java" },

  git = { label = "Git", cmd = "git", args = { "--version" }, category = "vcs" },
}

M._cache = {}

function M.define(name, definition)
  if type(name) ~= "string" or type(definition) ~= "table" then
    return nil, "invalid tool definition"
  end
  M.TOOLS[name] = vim.tbl_extend("force", { label = name, cmd = name, args = { "--version" } }, definition)
  M._cache[name] = nil
  return M.TOOLS[name]
end

function M.definition(tool)
  return M.TOOLS[tool] or { label = tool, cmd = tool, args = { "--version" } }
end

function M.tool_names()
  local names = {}
  for name in pairs(M.TOOLS) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

local function candidates(definition)
  local list = { { definition.cmd, unpack(definition.args or { "--version" }) } }
  for _, fallback in ipairs(definition.fallbacks or {}) do
    if type(fallback) == "table" and #fallback > 0 then
      list[#list + 1] = fallback
    end
  end
  return list
end

-- Cheap check that does not execute anything.
function M.is_available(tool)
  local definition = M.definition(tool)
  for _, argv in ipairs(candidates(definition)) do
    if process.executable(argv[1]) then
      return true
    end
  end
  return false
end

function M.clear_cache(tool)
  if tool then
    M._cache[tool] = nil
  else
    M._cache = {}
  end
end

local function cached(tool)
  local entry = M._cache[tool]
  if not entry then
    return nil
  end
  local ttl = config.get("runtime_cache_ttl") or 0
  if ttl <= 0 then
    return nil
  end
  if os.time() - entry.checked_at > ttl then
    M._cache[tool] = nil
    return nil
  end
  return entry
end

-- opts:
--   refresh = true  bypass/clear the cache
--   version = false skip executing the version command
--   timeout = ms   version command timeout (default 3000)
function M.info(tool, opts)
  opts = opts or {}
  if type(tool) ~= "string" or tool == "" then
    return nil, "tool name is required"
  end

  if not opts.refresh then
    local entry = cached(tool)
    if entry then
      local copy = vim.deepcopy(entry)
      copy.cached = true
      return copy
    end
  end

  local definition = M.definition(tool)
  local result = {
    name = tool,
    label = definition.label or tool,
    category = definition.category,
    found = false,
    path = nil,
    version = nil,
    raw = nil,
    command = nil,
    error = nil,
    checked_at = os.time(),
    cached = false,
  }

  for _, argv in ipairs(candidates(definition)) do
    if process.executable(argv[1]) then
      result.found = true
      result.command = utils.display_argv(argv)
      result.path = process.which(argv[1])
      if opts.version ~= false then
        local captured = process.run_sync(argv, {
          timeout = opts.timeout or 3000,
          env = { LC_ALL = "C" },
        })
        if captured then
          local output = (captured.stdout or "") .. "\n" .. (captured.stderr or "")
          result.raw = utils.trim(output)
          result.version = version.extract(output)
          if not result.version and captured.code ~= 0 then
            result.error = "version command exited with code " .. tostring(captured.code)
          end
        else
          result.error = "version check failed or timed out"
        end
      end
      break
    end
  end

  -- Only cache results that include version data. Caching an availability-only
  -- check would make a later version query look cached and skip the command.
  if opts.version ~= false then
    M._cache[tool] = vim.deepcopy(result)
  end
  return result
end

function M.detect(tools, opts)
  local results = {}
  for _, tool in ipairs(tools or {}) do
    results[tool] = M.info(tool, opts)
  end
  return results
end

function M.refresh(tools)
  tools = tools or M.tool_names()
  M.clear_cache()
  return M.detect(tools, { refresh = true })
end

function M.installed(tools)
  local installed, missing = {}, {}
  for _, tool in ipairs(tools or {}) do
    if M.is_available(tool) then
      installed[#installed + 1] = tool
    else
      missing[#missing + 1] = tool
    end
  end
  return installed, missing
end

return M
