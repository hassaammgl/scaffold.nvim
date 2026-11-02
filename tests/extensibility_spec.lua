-- Extension API tests: custom languages, templates, external templates.

local H = require("tests.harness")
local fs = require("scaffold.core.filesystem")
local templates = require("scaffold.templates")
local languages = require("scaffold.languages")
local project = require("scaffold.core.project")
local scaffold = require("scaffold")

H.test("custom languages can be registered and used", function()
  local language_id = H.unique("rust")
  local template_id = H.unique("rust-binary")

  local language, err = scaffold.register_language(language_id, {
    name = "Rust (test)",
    extensions = { "rs" },
    runtimes = { "rustc", "cargo" },
    build_systems = { "cargo" },
    templates = { template_id },
    markers = { "Cargo.toml" },
  })
  H.ok(language, err)
  H.ok(languages.exists(language_id))
  H.eq(languages.by_extension("main.rs").id, language_id)

  local template, template_err = scaffold.register_template({
    id = template_id,
    name = "Rust binary",
    language = language_id,
    files = {
      ["src/main.rs"] = 'fn main() { println!("Hello from {{project_name}}"); }\n',
      [".gitignore"] = "/target/\n",
    },
    commands = {
      build = { "cargo", "build" },
      run = { "cargo", "run" },
    },
  })
  H.ok(template, template_err)

  local base, projects = H.fresh()
  local record, meta = project.create({
    name = "rusty",
    language = language_id,
    template = template_id,
    parent_dir = projects,
    git = false,
  })
  H.ok(record, meta)
  H.eq(record.language, language_id)
  H.eq(record.commands.build, { "cargo", "build" })
  H.match(H.read(record.path .. "/src/main.rs"), "Hello from rusty")
  H.rmrf(base)
end)

H.test("invalid language definitions are rejected", function()
  local bad_id, id_err = scaffold.register_language("Invalid Id", { name = "X" })
  H.falsy(bad_id)
  H.ok(id_err ~= nil)

  local bad_def, def_err = scaffold.register_language(H.unique("lang"), { extensions = { "x" } })
  H.falsy(bad_def)
  H.match(tostring(def_err), "'name' is required")

  local bad_list, list_err = scaffold.register_language(H.unique("lang"), {
    name = "X",
    extensions = "x",
  })
  H.falsy(bad_list)
  H.match(tostring(list_err), "must be a list")
end)

H.test("duplicate template registration is refused", function()
  local id = H.unique("dup")
  local template = {
    id = id,
    name = "Dup",
    language = "cpp",
    files = { ["x.txt"] = "x" },
  }
  local first = H.ok(scaffold.register_template(template))
  H.eq(first.id, id)
  local second, err = scaffold.register_template(template)
  H.falsy(second)
  H.match(tostring(err), "already registered")
end)

H.test("external template directories load in a restricted environment", function()
  local base = vim.fn.tempname()
  H.mkdir(base)
  local good_id = H.unique("external")
  H.write(base .. "/good.lua", ([[
return {
  templates = {
    {
      id = %q,
      name = "External",
      language = "cpp",
      files = {
        ["src/main.cpp"] = "int main() { return 0; }",
      },
    },
  },
}
]]):format(good_id))

  local loaded, errors = templates.load_external(base)
  H.eq(#errors, 0)
  H.eq(#loaded, 1)
  H.eq(loaded[1], good_id)
  H.ok(templates.exists(good_id))

  local bad_dir = vim.fn.tempname()
  H.mkdir(bad_dir)
  H.write(bad_dir .. "/bad.lua", "return { templates = { { id = 'bad', files = { x = tostring(os.time()) } } } }")
  local loaded_bad, errors_bad = templates.load_external(bad_dir)
  H.eq(#loaded_bad, 0)
  H.eq(#errors_bad, 1)
  H.match(errors_bad[1], "bad.lua")

  local missing_loaded, missing_errors = templates.load_external("/definitely/not/a/template/dir")
  H.eq(#missing_loaded, 0)
  H.eq(#missing_errors, 1)

  H.rmrf(base)
  H.rmrf(bad_dir)
end)

H.test("external templates cannot write outside the destination", function()
  local base = vim.fn.tempname()
  H.mkdir(base)
  local id = H.unique("escape")
  H.write(base .. "/escape.lua", ([[
return {
  templates = {
    {
      id = %q,
      name = "Escape",
      language = "cpp",
      files = { ["../escape.txt"] = "no" },
    },
  },
}
]]):format(id))

  local loaded, errors = templates.load_external(base)
  H.eq(#loaded, 0)
  H.eq(#errors, 1)
  H.ok(not fs.exists(vim.fn.fnamemodify(base, ":h") .. "/escape.txt"))
  H.rmrf(base)
end)

H.test("user commands are registered exactly once with descriptions", function()
  require("scaffold.commands").register()
  require("scaffold.commands").register()

  local commands = vim.api.nvim_get_commands({})
  local expected = {
    "Scaffold",
    "ScaffoldCreate",
    "ScaffoldOpen",
    "ScaffoldRecent",
    "ScaffoldDetect",
    "ScaffoldBuild",
    "ScaffoldTest",
    "ScaffoldRun",
    "ScaffoldClean",
    "ScaffoldTools",
    "ScaffoldDoctor",
    "ScaffoldInstall",
    "ScaffoldTemplates",
    "ScaffoldRemove",
    "ScaffoldCancel",
  }
  for _, name in ipairs(expected) do
    H.ok(commands[name] ~= nil, "missing command :" .. name)
    local description = commands[name].desc or commands[name].definition
    H.ok(description and description ~= "", "missing description for :" .. name)
  end
end)

H.test("health check runs without error", function()
  local health = require("scaffold.health")
  local ok, err = pcall(health.check)
  H.ok(ok, err)
end)
