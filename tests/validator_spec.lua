-- Validation and path-safety tests.

local H = require("tests.harness")
local validator = require("forge.core.validator")

H.test("project names accept safe values", function()
  for _, name in ipairs({ "app", "my-app", "my_app", "v1.2.3", "A1" }) do
    local ok, normalized = validator.project_name(name)
    H.ok(ok, ("expected '%s' to be valid: %s"):format(name, tostring(normalized)))
    H.eq(normalized, name)
  end
end)

H.test("project names reject traversal and unsafe values", function()
  local invalid = {
    "",
    "   ",
    "..",
    "../evil",
    "a/b",
    "a\\b",
    "-flag",
    ".hidden",
    "with space",
    "a..b",
    string.rep("a", 65),
  }
  for _, name in ipairs(invalid) do
    local ok = validator.project_name(name)
    H.falsy(ok, ("expected '%s' to be rejected"):format(name))
  end
  H.falsy(validator.project_name(nil))
  H.falsy(validator.project_name(42))
end)

H.test("relative template paths reject traversal and absolute paths", function()
  H.ok(validator.relative_path("src/main.c"))
  H.ok(validator.relative_path("nested/dir/file.txt"))
  for _, path in ipairs({ "../evil", "a/../../evil", "/etc/passwd", "a//b", "a/./b", "a/", "a\\b", "" }) do
    H.falsy(validator.relative_path(path), ("expected '%s' to be rejected"):format(path))
  end
  H.falsy(validator.relative_path(nil))
end)

H.test("destination checks reject files, non-empty dirs, and root", function()
  local base = vim.fn.tempname()
  H.mkdir(base)

  H.ok(validator.destination(base .. "/new-project"))

  H.mkdir(base .. "/nonempty")
  H.write(base .. "/nonempty/file.txt", "x")
  H.falsy(validator.destination(base .. "/nonempty"), "non-empty destination should be rejected")

  H.mkdir(base .. "/empty")
  H.ok(validator.destination(base .. "/empty"), "empty destination should be allowed")

  H.write(base .. "/file", "x")
  H.falsy(validator.destination(base .. "/file"), "file destination should be rejected")
  H.falsy(validator.destination("/"), "root destination should be rejected")

  H.falsy(validator.destination(base .. "/a/b", { allow_missing_parent = false }))
  H.ok(validator.destination(base .. "/a/b", { allow_missing_parent = true }))

  H.rmrf(base)
end)

H.test("command validation requires a non-empty string argv array", function()
  H.ok(validator.command({ "gcc", "main.c" }))
  H.ok(validator.command({ "echo", "" }) == nil, "empty argument must be rejected")
  H.falsy(validator.command({}))
  H.falsy(validator.command({ 1, 2 }))
  H.falsy(validator.command("echo hi"))
  H.falsy(validator.command(nil))
  H.falsy(validator.command({ "echo", "a\0b" }))
end)

H.test("project config validation rejects shell-style commands", function()
  H.ok(validator.project_config({
    language = "typescript",
    commands = { build = { "bun", "run", "build" } },
  }))
  H.falsy(validator.project_config({
    commands = { build = "bun run build" },
  }))
  H.falsy(validator.project_config({
    commands = { build = { "bun", "" } },
  }))
  H.falsy(validator.project_config({
    language = "Not A Language",
  }))
  H.falsy(validator.project_config({
    commands = { build = { argv = { "make" }, cwd = 5 } },
  }))
end)
