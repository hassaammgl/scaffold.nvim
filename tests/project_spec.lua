-- Project creation, opening, and project configuration tests.

local H = require("tests.harness")
local fs = require("forge.core.filesystem")
local registry = require("forge.core.registry")
local project = require("forge.core.project")

local function create(projects, overrides)
  local opts = {
    language = "cpp",
    template = "cpp-cmake",
    parent_dir = projects,
    git = false,
    open = false,
    options = { standard = "20" },
  }
  for key, value in pairs(overrides or {}) do
    opts[key] = value
  end
  return require("forge").create_project(opts)
end

H.test("create writes template files and registers metadata", function()
  local base, projects = H.fresh()
  local record, meta = create(projects, { name = "cpp-app" })
  H.ok(record, meta)
  H.eq(record.name, "cpp-app")
  H.eq(record.language, "cpp")
  H.eq(record.template, "cpp-cmake")
  H.eq(record.runtime, "g++")
  H.eq(record.build_system, "cmake")
  H.eq(record.path, fs.expand(projects .. "/cpp-app"))

  H.ok(fs.is_file(record.path .. "/CMakeLists.txt"))
  H.ok(fs.is_file(record.path .. "/src/main.cpp"))
  H.match(H.read(record.path .. "/CMakeLists.txt"), "CMAKE_CXX_STANDARD 20")
  H.match(H.read(record.path .. "/src/main.cpp"), "Hello from cpp-app")
  H.match(H.read(record.path .. "/README.md"), "cpp-app")

  H.eq(record.commands.build, { "cmake", "--build", "build" })
  H.eq(record.commands.run, { "./build/cpp-app" })
  H.eq(#meta.created, 4)
  H.eq(#meta.install_commands, 0)
  H.eq(registry.get(record.id).path, record.path)
  H.rmrf(base)
end)

H.test("dry run creates nothing", function()
  local base, projects = H.fresh()
  local plan = project.create({
    name = "dry-run",
    language = "cpp",
    template = "cpp-make",
    parent_dir = projects,
    options = { standard = "17" },
    dry_run = true,
  })
  H.ok(plan)
  H.ok(plan.operations and #plan.operations > 0)
  H.falsy(fs.exists(projects .. "/dry-run"))
  H.rmrf(base)
end)

H.test("duplicate project creation is refused without overwriting", function()
  local base, projects = H.fresh()
  local record = H.ok(create(projects, { name = "twice" }))
  local original = H.read(record.path .. "/CMakeLists.txt")

  local second, err = create(projects, { name = "twice" })
  H.falsy(second)
  H.match(tostring(err), "not empty")
  H.eq(H.read(record.path .. "/CMakeLists.txt"), original)
  H.rmrf(base)
end)

H.test("library template omits run/test commands and main.cpp", function()
  local base, projects = H.fresh()
  local record, meta = create(projects, {
    name = "cpp-lib",
    options = { standard = "23", kind = "library" },
  })
  H.ok(record, meta)
  H.falsy(fs.exists(record.path .. "/src/main.cpp"))
  H.ok(fs.is_file(record.path .. "/src/lib.cpp"))
  H.ok(fs.is_file(record.path .. "/include/cpp-lib/lib.hpp"))
  H.falsy(record.commands.run)
  H.falsy(record.commands.test)
  H.rmrf(base)
end)

H.test("invalid template/language combinations are refused", function()
  local base, projects = H.fresh()
  local record, err = project.create({
    name = "mismatch",
    language = "python",
    template = "cpp-cmake",
    parent_dir = projects,
  })
  H.falsy(record)
  H.match(tostring(err), "belongs to language")

  local unknown, unknown_err = project.create({
    name = "unknown",
    language = "brainfuck",
    parent_dir = projects,
  })
  H.falsy(unknown)
  H.match(tostring(unknown_err), "unknown language")
  H.rmrf(base)
end)

H.test("python-cli template generates a valid src layout and commands", function()
  local base, projects = H.fresh()
  local record, meta = create(projects, {
    name = "my-cli",
    language = "python",
    template = "python-cli",
    runtime = "python3",
    options = {},
  })
  H.ok(record, meta)
  H.ok(fs.is_file(record.path .. "/pyproject.toml"))
  H.ok(fs.is_file(record.path .. "/src/my_cli/cli.py"))
  H.ok(fs.is_file(record.path .. "/tests/test_cli.py"))
  H.match(H.read(record.path .. "/pyproject.toml"), 'name = "my-cli"')
  H.match(H.read(record.path .. "/pyproject.toml"), 'my-cli = "my_cli.cli:main"')
  H.eq(record.commands.run, { "python3", "-m", "my_cli" })
  H.eq(record.commands.test, { "python3", "-m", "unittest", "discover", "-s", "tests", "-v" })
  H.eq(#meta.install_commands, 2)
  H.rmrf(base)
end)

H.test("javascript template respects the selected package manager", function()
  local base, projects = H.fresh()
  local record, meta = create(projects, {
    name = "web-app",
    language = "javascript",
    template = "js-vanilla",
    runtime = "node",
    package_manager = "npm",
    options = {},
  })
  H.ok(record, meta)
  H.ok(fs.is_file(record.path .. "/package.json"))
  H.ok(fs.is_file(record.path .. "/src/index.js"))
  H.match(H.read(record.path .. "/package.json"), '"name": "web-app"')
  H.eq(record.commands.run, { "npm", "run", "start" })
  H.eq(record.commands.test, { "npm", "test" })
  H.eq(meta.install_commands[1].argv, { "npm", "install" })
  H.rmrf(base)
end)

H.test("java-maven template renders the selected release", function()
  local base, projects = H.fresh()
  local record, meta = create(projects, {
    name = "java-app",
    language = "java",
    template = "java-maven",
    runtime = "java",
    options = { release = "17" },
  })
  H.ok(record, meta)
  H.ok(fs.is_file(record.path .. "/pom.xml"))
  H.ok(fs.is_file(record.path .. "/src/main/java/com/example/App.java"))
  H.match(H.read(record.path .. "/pom.xml"), "<maven.compiler.release>17</maven.compiler.release>")
  H.eq(record.commands.run, { "mvn", "-q", "exec:java" })
  H.match(meta.install_commands[1].argv[1], "mvn")
  H.rmrf(base)
end)

H.test("declarative .forge.json configuration is read automatically", function()
  local base, projects = H.fresh()
  local record = H.ok(create(projects, { name = "configured" }))
  H.write(record.path .. "/.forge.json", vim.json.encode({
    commands = {
      build = { "echo", "json-build" },
      test = { argv = { "echo", "json-test" }, cwd = "src" },
    },
  }))

  local config, meta = project.config(record.path)
  H.ok(config, meta)
  H.eq(config.commands.build, { "echo", "json-build" })
  H.eq(meta.executable, false)
  H.match(meta.source, ".forge.json")
  H.rmrf(base)
end)

H.test(".forge.lua requires explicit approval and runs sandboxed", function()
  local base = vim.fn.tempname()
  H.mkdir(base)
  H.write(base .. "/.forge.lua", [[
return {
  commands = {
    test = { "echo", "lua-test" },
  },
}
]])

  local blocked, blocked_err = project.config(base, { approve = false })
  H.falsy(blocked)
  H.match(tostring(blocked_err), "not approved")

  local config, meta = project.config(base, { approved = true })
  H.ok(config, meta)
  H.eq(config.commands.test, { "echo", "lua-test" })
  H.eq(meta.executable, true)

  local sandbox_dir = vim.fn.tempname()
  H.mkdir(sandbox_dir)
  H.write(sandbox_dir .. "/.forge.lua", "return { value = os.time() }")
  local sandboxed, sandbox_err = project.config(sandbox_dir, { approved = true })
  H.falsy(sandboxed)
  H.ok(sandbox_err ~= nil)
  H.rmrf(base)
  H.rmrf(sandbox_dir)
end)

H.test("open changes directory, updates last_opened, and keeps metadata", function()
  local base, projects = H.fresh()
  local record = H.ok(create(projects, { name = "openable" }))
  local original_cwd = vim.fn.getcwd()

  local ok, opened = project.open(record)
  H.ok(ok, opened)
  H.eq(vim.fn.getcwd(), record.path)
  H.eq(opened.id, record.id)
  H.ok(registry.get(record.id).last_opened > 0)

  vim.fn.chdir(original_cwd)
  H.rmrf(base)
end)

H.test("current project resolution finds a registered parent", function()
  local base, projects = H.fresh()
  local record = H.ok(create(projects, { name = "nested" }))
  H.mkdir(record.path .. "/src/nested")
  local original_cwd = vim.fn.getcwd()
  vim.fn.chdir(record.path .. "/src/nested")

  local current = project.current()
  H.ok(current)
  H.eq(current.id, record.id)

  vim.fn.chdir(original_cwd)
  H.rmrf(base)
end)

H.test("create parent directory when requested", function()
  local base = vim.fn.tempname()
  H.mkdir(base)
  local projects = base .. "/does/not/exist/yet"
  require("forge").setup({
    projects_dir = projects,
    registry_path = base .. "/registry.json",
    notify_on_exit = false,
  })
  registry._reset()

  local record, err = project.create({
    name = "nested-parent",
    language = "c",
    template = "c-make",
    parent_dir = projects,
    options = { standard = "17" },
    git = false,
  })
  H.ok(record, err)
  H.ok(fs.is_dir(projects))
  H.ok(fs.is_file(projects .. "/nested-parent/Makefile"))
  H.rmrf(base)
end)
