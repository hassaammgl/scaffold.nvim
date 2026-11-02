-- Build command resolution and process execution tests.

local H = require("tests.harness")
local fs = require("forge.core.filesystem")
local registry = require("forge.core.registry")
local project = require("forge.core.project")
local build = require("forge.managers.build")
local process = require("forge.core.process")

local function create_cpp(projects, name)
  return H.ok(project.create({
    name = name,
    language = "cpp",
    template = "cpp-cmake",
    parent_dir = projects,
    options = { standard = "20" },
    git = false,
  }))
end

H.test("new CMake projects configure before building", function()
  local base, projects = H.fresh()
  local record = create_cpp(projects, "resolved")

  local configure = H.ok(build.resolve(record, "build"))
  H.eq(configure.source, "registry")
  H.eq(configure.argv[1], "cmake")
  H.eq(configure.argv[2], "-S")
  H.eq(configure.cwd, record.path)
  H.eq(configure.confirm, false)
  H.ok(configure.note ~= nil)

  H.mkdir(record.path .. "/build")
  local spec = H.ok(build.resolve(record, "build"))
  H.eq(spec.source, "registry")
  H.eq(spec.argv, { "cmake", "--build", "build" })
  H.eq(spec.cwd, record.path)
  H.eq(spec.confirm, false)
  H.rmrf(base)
end)

H.test(".forge.json commands require confirmation and support cwd", function()
  local base, projects = H.fresh()
  local record = create_cpp(projects, "configured")
  H.mkdir(record.path .. "/sub")
  H.write(record.path .. "/.forge.json", vim.json.encode({
    commands = {
      build = { argv = { "make", "-C", "sub" }, cwd = "sub" },
    },
  }))

  local spec = H.ok(build.resolve(record, "build"))
  H.eq(spec.argv, { "make", "-C", "sub" })
  H.eq(spec.cwd, record.path .. "/sub")
  H.eq(spec.confirm, true)
  H.match(tostring(spec.source), ".forge.json")
  H.rmrf(base)
end)

H.test("explicit argv is validated and bypasses project heuristics", function()
  local base, projects = H.fresh()
  local record = create_cpp(projects, "explicit")

  local spec = H.ok(build.resolve(record, "build", { argv = { "echo", "hello" } }))
  H.eq(spec.argv, { "echo", "hello" })
  H.eq(spec.source, "explicit")

  local invalid, err = build.resolve(record, "build", { argv = { "echo", "" } })
  H.falsy(invalid)
  H.match(tostring(err), "must not be empty")
  H.rmrf(base)
end)

H.test("CMake heuristics configure first, then build", function()
  local base, projects = H.fresh()
  local path = projects .. "/raw-cmake"
  H.mkdir(path)
  H.write(path .. "/CMakeLists.txt", "project(raw CXX)\n")
  H.write(path .. "/main.cpp", "int main(){return 0;}\n")
  local record = H.ok(registry.register({ name = "raw-cmake", path = path, language = "cpp" }))

  local configure = H.ok(build.resolve(record, "build"))
  H.eq(configure.source, "heuristic")
  H.eq(configure.argv[1], "cmake")
  H.eq(configure.argv[2], "-S")
  H.ok(configure.note ~= nil)

  H.mkdir(path .. "/build")
  local compile = H.ok(build.resolve(record, "build"))
  H.eq(compile.argv, { "cmake", "--build", "build" })
  H.eq(compile.confirm, false)
  H.rmrf(base)
end)

H.test("Makefile projects resolve make commands", function()
  local base, projects = H.fresh()
  local path = projects .. "/raw-make"
  H.mkdir(path)
  H.write(path .. "/Makefile", "all:\n\ttrue\n")
  H.write(path .. "/main.c", "int main(void){return 0;}\n")
  local record = H.ok(registry.register({ name = "raw-make", path = path, language = "c" }))

  local spec = H.ok(build.resolve(record, "build"))
  H.eq(spec.argv, { "make" })
  H.eq(spec.build_system, "make")

  local clean = H.ok(build.resolve(record, "clean"))
  H.eq(clean.argv, { "make", "clean" })
  H.eq(clean.confirm, true, "clean commands must always ask for confirmation")

  local run, run_err = build.resolve(record, "run")
  H.falsy(run)
  H.match(tostring(run_err), "no executable found")
  H.rmrf(base)
end)

H.test("unknown project kinds fail cleanly", function()
  local base, projects = H.fresh()
  local record = create_cpp(projects, "unknown-kind")
  local spec, err = build.resolve(record, "deploy")
  H.falsy(spec)
  H.ok(err ~= nil)

  local missing, missing_err = build.resolve({ path = projects .. "/missing" }, "build")
  H.falsy(missing)
  H.match(tostring(missing_err), "does not exist")
  H.rmrf(base)
end)

H.test("preview is human readable and contains the working directory", function()
  local base, projects = H.fresh()
  local record = create_cpp(projects, "preview")
  local lines = build.preview(record, "build")
  local text = table.concat(lines, "\n")
  H.match(text, "build command")
  H.match(text, "cmake")
  H.match(text, record.path)
  H.rmrf(base)
end)

H.test("process environment keeps PATH and HOME", function()
  local home = process.run_sync({ "sh", "-c", "printf '%s' \"$HOME\"" }, { timeout = 5000 })
  H.ok(home)
  H.eq(home.code, 0)
  H.ok(home.stdout ~= "", "HOME must be inherited by child processes")

  local path = process.run_sync({ "sh", "-c", "printf '%s' \"$PATH\"" }, { timeout = 5000 })
  H.ok(path)
  H.eq(path.code, 0)
  H.ok(path.stdout:find("/", 1, true) ~= nil)
end)

H.test("process failures report exit codes and capture stderr", function()
  local result = process.run_sync({ "sh", "-c", "echo out; echo err >&2; exit 3" }, { timeout = 5000 })
  H.ok(result)
  H.eq(result.code, 3)
  H.match(result.stdout, "out")
  H.match(result.stderr, "err")

  local missing = process.run_sync({ "forge-definitely-not-a-real-tool" }, { timeout = 5000 })
  H.falsy(missing)
end)

H.test("argv arrays are not interpreted by a shell", function()
  local result = process.run_sync({ "printf", "%s", "$HOME; rm -rf /" }, { timeout = 5000 })
  H.ok(result)
  H.eq(result.stdout, "$HOME; rm -rf /")
end)
