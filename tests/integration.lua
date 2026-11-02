-- Real-environment smoke test.
--
-- Creates projects from built-in templates and runs the generated build/test
-- commands with the actual toolchains installed on this machine. This is not
-- part of tests/run.lua because it requires compilers and runtimes.
--
--   nvim --headless --clean -u NONE -l tests/integration.lua
--
-- Set FORGE_KEEP_INTEGRATION=1 to keep the temporary project directory.

vim.opt.runtimepath:prepend(vim.fn.getcwd())

local root = vim.fn.tempname()
local projects = root .. "/projects"
require("forge.core.filesystem").mkdirp(projects)

local forge = require("forge")
forge.setup({
  projects_dir = projects,
  registry_path = root .. "/registry.json",
  open_after_create = false,
  notify_on_exit = false,
})

local build = require("forge.managers.build")
local checks = {}

local function run(argv, cwd, label)
  local result = vim.system(argv, { cwd = cwd, text = true }):wait()
  local output = (result.stdout or "") .. (result.stderr or "")
  if result.code ~= 0 then
    error(("%s failed (%d): %s\n%s"):format(label, result.code, table.concat(argv, " "), output))
  end
  checks[#checks + 1] = ("%-20s ok  %s"):format(label, table.concat(argv, " "))
  return output
end

local function make(name, language, template, options, extra)
  local opts = vim.tbl_extend("force", {
    name = name,
    language = language,
    template = template,
    parent_dir = projects,
    options = options or {},
    git = false,
  }, extra or {})
  local record, meta = forge.create_project(opts)
  if not record then
    error(("%s: %s"):format(name, tostring(meta)))
  end
  return record
end

-- C++ / CMake: configure, compile, execute.
local cpp = make("real-cpp", "cpp", "cpp-cmake", { standard = "20" })
local spec = assert(build.resolve(cpp, "build"))
run(spec.argv, spec.cwd, "cmake configure")
spec = assert(build.resolve(cpp, "build"))
run(spec.argv, spec.cwd, "cmake build")
local cpp_out = run({ cpp.path .. "/build/real-cpp" }, cpp.path, "cpp binary")
assert(cpp_out:find("Hello from real-cpp", 1, true), "unexpected C++ output: " .. cpp_out)

-- C++ / Make.
local make_cpp = make("real-make", "cpp", "cpp-make", { standard = "17" })
spec = assert(build.resolve(make_cpp, "build"))
run(spec.argv, spec.cwd, "make build")
local make_out = run({ make_cpp.path .. "/real-make" }, make_cpp.path, "make binary")
assert(make_out:find("Hello from real-make", 1, true), "unexpected Make output: " .. make_out)

-- JavaScript: node:test through npm.
local js = make("real-js", "javascript", "js-vanilla", {}, { package_manager = "npm" })
spec = assert(build.resolve(js, "test"))
run(spec.argv, spec.cwd, "npm test")

-- Python: unittest discovery in the generated src layout.
local py = make("real-py", "python", "python-cli")
spec = assert(build.resolve(py, "test"))
run(spec.argv, spec.cwd, "python unittest")

-- Bun: bun:test.
local bun = make("real-bun", "bun", "bun-ts", {})
spec = assert(build.resolve(bun, "test"))
run(spec.argv, spec.cwd, "bun test")

print("Forge.nvim integration smoke test")
print(("%d checks passed"):format(#checks))
for _, line in ipairs(checks) do
  print("  " .. line)
end
print("projects: " .. projects)

if vim.env.FORGE_KEEP_INTEGRATION ~= "1" then
  vim.fn.delete(root, "rf")
end
