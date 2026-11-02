-- Template engine tests.

local H = require("tests.harness")
local templates = require("forge.templates")
local renderer = require("forge.templates.renderer")
local fs = require("forge.core.filesystem")

H.test("all built-in templates pass validation", function()
  templates.load_builtins()
  local list = templates.list()
  H.ok(#list >= 14, "expected at least 14 built-in templates, got " .. #list)
  for _, template in ipairs(list) do
    local errors = templates.validate(template)
    H.eq(#errors, 0, ("template %s failed validation: %s"):format(template.id, table.concat(errors, "; ")))
  end
end)

H.test("template string rendering reports unresolved variables", function()
  local rendered, unresolved = renderer.render_string("{{project_name}} at {{project_path}}", {
    project_name = "demo",
  })
  H.eq(rendered, "demo at {{project_path}}")
  H.eq(unresolved, { "project_path" })

  local clean, none = renderer.render_string("{{a}}-{{b}}", { a = "1", b = "2" })
  H.eq(clean, "1-2")
  H.eq(#none, 0)
end)

H.test("render context provides slugs, modules, and option aliases", function()
  local ctx = renderer.context({ id = "tpl", language = "cpp" }, {
    project_name = "My App",
    language = "cpp",
    runtime = "g++",
    options = { standard = "20" },
  })
  H.eq(ctx.project_name, "My App")
  H.eq(ctx.project_slug, "my-app")
  H.eq(ctx.project_module, "my_app")
  H.eq(ctx.selected_language, "cpp")
  H.eq(ctx.selected_runtime, "g++")
  H.eq(ctx.standard, "20")
  H.eq(ctx.selected_standard, "20")
end)

H.test("option defaults and validation", function()
  local template = {
    options = {
      standard = { type = "select", values = { "17", "20" }, default = "20" },
      feature = { type = "confirm", default = true },
      name = { type = "input", default = "x" },
    },
  }
  local values, err = renderer.apply_defaults(template, {})
  H.ok(values, err)
  H.eq(values.standard, "20")
  H.eq(values.feature, true)
  H.eq(values.name, "x")

  H.falsy(renderer.apply_defaults(template, { standard = "23" }))
  H.falsy(renderer.apply_defaults(template, { feature = "yes" }))
end)

H.test("template registration rejects unsafe paths", function()
  local id = H.unique("unsafe")
  local template = {
    id = id,
    name = "Unsafe",
    language = "cpp",
    files = { ["../escape.txt"] = "no" },
  }
  local errors = templates.validate(template)
  H.ok(#errors > 0)
  local registered, err = templates.register(template)
  H.falsy(registered)
  H.match(tostring(err), "path traversal")

  local no_files, no_files_err = templates.register({
    id = H.unique("empty"),
    name = "Empty",
    language = "cpp",
    files = {},
  })
  H.falsy(no_files)
  H.ok(no_files_err ~= nil)
end)

H.test("plan renders file paths and contents safely", function()
  local dest = vim.fn.tempname()
  H.mkdir(dest)
  local template = {
    id = H.unique("render"),
    name = "Render",
    language = "cpp",
    options = { value = { type = "input", default = "hello" } },
    files = {
      ["src/{{project_slug}}.txt"] = "{{project_name}} says {{value}}\n",
      ["static.txt"] = "static\n",
    },
  }
  local ctx = renderer.context(template, {
    project_name = "demo",
    project_path = dest,
    language = "cpp",
    options = { value = "hi" },
  })
  local plan = renderer.plan(template, ctx, dest)
  H.eq(#plan.errors, 0)
  H.eq(#plan.operations, 2)

  local result, err = renderer.apply(plan)
  H.ok(result, err)
  H.eq(#result.created, 2)
  H.eq(H.read(dest .. "/src/demo.txt"), "demo says hi\n")
  H.eq(H.read(dest .. "/static.txt"), "static\n")
  H.rmrf(dest)
end)

H.test("apply never overwrites existing files by default", function()
  local dest = vim.fn.tempname()
  H.mkdir(dest)
  H.write(dest .. "/README.md", "keep me")

  local template = {
    id = H.unique("overwrite"),
    name = "Overwrite",
    language = "cpp",
    files = { ["README.md"] = "replace me" },
  }
  local ctx = renderer.context(template, { project_name = "demo", project_path = dest })
  local plan = renderer.plan(template, ctx, dest)
  H.eq(plan.operations[1].exists, true)
  local result = H.ok(renderer.apply(plan))
  H.eq(#result.created, 0)
  H.eq(#result.skipped, 1)
  H.eq(H.read(dest .. "/README.md"), "keep me")

  local plan2 = renderer.plan(template, ctx, dest)
  local forced = H.ok(renderer.apply(plan2, { overwrite = true }))
  H.eq(#forced.created, 1)
  H.eq(H.read(dest .. "/README.md"), "replace me")
  H.rmrf(dest)
end)

H.test("unresolved variables fail the plan instead of writing literals", function()
  local dest = vim.fn.tempname()
  H.mkdir(dest)
  local template = {
    id = H.unique("missing"),
    name = "Missing",
    language = "cpp",
    files = { ["a.txt"] = "{{not_defined}}" },
  }
  local ctx = renderer.context(template, { project_name = "demo" })
  local plan = renderer.plan(template, ctx, dest)
  H.ok(#plan.errors > 0)
  H.match(table.concat(plan.errors, " "), "not_defined")
  local result, err = renderer.apply(plan)
  H.falsy(result)
  H.match(tostring(err), "errors")
  H.falsy(fs.exists(dest .. "/a.txt"))
  H.rmrf(dest)
end)

H.test("command resolution supports functions and placeholders", function()
  local ctx = renderer.context({ id = "x", language = "cpp" }, { project_name = "demo" })
  local argv, cwd, err = renderer.resolve_command(function(context)
    return { "echo", context.project_name }
  end, ctx)
  H.ok(argv, err)
  H.eq(argv, { "echo", "demo" })
  H.eq(cwd, nil)

  local with_placeholder, _, placeholder_err = renderer.resolve_command({ "echo", "{{project_slug}}" }, ctx)
  H.ok(with_placeholder, placeholder_err)
  H.eq(with_placeholder[2], "demo")

  local invalid, _, invalid_err = renderer.resolve_command({ "echo", "" }, ctx)
  H.falsy(invalid)
  H.ok(invalid_err ~= nil)

  local function_error, _, function_err = renderer.resolve_command(function()
    error("boom")
  end, ctx)
  H.falsy(function_error)
  H.match(tostring(function_err), "boom")
end)
