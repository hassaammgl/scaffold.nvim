-- Project registry tests.

local H = require("tests.harness")
local fs = require("forge.core.filesystem")
local registry = require("forge.core.registry")

local function make_project(projects, name)
  local path = projects .. "/" .. name
  H.mkdir(path)
  return path
end

H.test("register persists schema-tagged metadata and prevents duplicates", function()
  local base, projects = H.fresh()
  local path = make_project(projects, "alpha")

  local record, err = registry.register({ name = "alpha", path = path, language = "cpp" })
  H.ok(record, err)
  H.ok(record.id)
  H.eq(record.name, "alpha")
  H.eq(record.path, fs.expand(path))
  H.eq(record.created_at ~= nil, true)

  H.ok(fs.exists(base .. "/registry.json"))
  local decoded = vim.json.decode(H.read(base .. "/registry.json"))
  H.eq(decoded.schema_version, 1)

  H.eq(registry.get(record.id).name, "alpha")
  H.eq(registry.find_by_path(path).id, record.id)

  local duplicate_path, duplicate_err = registry.register({ name = "alpha-two", path = path })
  H.falsy(duplicate_path)
  H.match(tostring(duplicate_err), "already registered")

  local beta_path = make_project(projects, "beta")
  local duplicate_id, id_err = registry.register({ id = record.id, name = "beta", path = beta_path })
  H.falsy(duplicate_id)
  H.match(tostring(id_err), "already exists")
  H.rmrf(base)
end)

H.test("register rejects missing paths and invalid names", function()
  local base, projects = H.fresh()
  local missing, err = registry.register({ name = "ghost", path = projects .. "/ghost" })
  H.falsy(missing)
  H.match(tostring(err), "not a directory")

  H.mkdir(projects .. "/bad")
  local invalid, invalid_err = registry.register({ name = "../bad", path = projects .. "/bad" })
  H.falsy(invalid)
  H.ok(invalid_err ~= nil)
  H.rmrf(base)
end)

H.test("unregister removes metadata but never the project directory", function()
  local base, projects = H.fresh()
  local path = make_project(projects, "keep-me")
  local record = H.ok(registry.register({ name = "keep-me", path = path }))

  local removed, err = registry.unregister(record.id)
  H.ok(removed, err)
  H.eq(removed.name, "keep-me")
  H.falsy(registry.get(record.id))
  H.ok(fs.is_dir(path), "project directory must still exist after unregister")
  H.ok(fs.is_dir(fs.dirname(path)), "project parent must still exist after unregister")

  local again, again_err = registry.unregister(record.id)
  H.falsy(again)
  H.match(tostring(again_err), "not registered")
  H.rmrf(base)
end)

H.test("rename only changes registry metadata", function()
  local base, projects = H.fresh()
  local path = make_project(projects, "original")
  local record = H.ok(registry.register({ name = "original", path = path }))

  local renamed, err = registry.rename(record.id, "display-name")
  H.ok(renamed, err)
  H.eq(renamed.name, "display-name")
  H.eq(renamed.path, fs.expand(path))
  H.ok(fs.is_dir(path))
  H.eq(fs.basename(path), "original")
  H.rmrf(base)
end)

H.test("update validates commands and can set last_opened", function()
  local base, projects = H.fresh()
  local path = make_project(projects, "updatable")
  local record = H.ok(registry.register({ name = "updatable", path = path }))

  local updated, err = registry.update(record.id, {
    commands = { build = { "make", "all" } },
    last_opened = 12345,
  })
  H.ok(updated, err)
  H.eq(updated.commands.build, { "make", "all" })
  H.eq(updated.last_opened, 12345)

  local invalid, invalid_err = registry.update(record.id, { commands = { build = "make all" } })
  H.falsy(invalid)
  H.ok(invalid_err ~= nil)
  H.rmrf(base)
end)

H.test("recent and search return expected metadata", function()
  local base, projects = H.fresh()
  local names = { "zebra", "alpha", "middle" }
  local records = {}
  for _, name in ipairs(names) do
    local path = make_project(projects, name)
    records[name] = H.ok(registry.register({ name = name, path = path, language = "python" }))
  end

  registry.update(records.alpha.id, { last_opened = 100 })
  registry.update(records.zebra.id, { last_opened = 200 })

  local recent = registry.recent(10)
  H.eq(recent[1].name, "zebra")
  H.eq(recent[2].name, "alpha")

  local results = registry.search("alph")
  H.eq(#results, 1)
  H.eq(results[1].name, "alpha")

  H.eq(#registry.search("python"), 3)
  H.eq(#registry.search(""), 3)

  local all = registry.all()
  H.eq(all[1].name, "alpha")
  H.eq(all[3].name, "zebra")
  H.rmrf(base)
end)

H.test("corrupted registry is backed up and recovered as empty", function()
  local base, projects = H.fresh()
  H.write(base .. "/registry.json", "{ this is not json")

  registry._reset()
  local data = registry.load(true)
  H.eq(vim.tbl_count(data.projects), 0)
  H.eq(data.schema_version, 1)

  local backups = vim.fn.glob(base .. "/registry.json.corrupt-*", false, true)
  H.eq(#backups, 1)
  H.match(H.read(backups[1]), "this is not json")

  -- Recovery: registration still works after a corrupt file.
  local path = make_project(projects, "recovered")
  local record, err = registry.register({ name = "recovered", path = path })
  H.ok(record, err)
  registry._reset()
  H.eq(registry.get(record.id).name, "recovered")
  H.rmrf(base)
end)

H.test("older schema versions migrate to the current schema", function()
  local base, projects = H.fresh()
  local path = make_project(projects, "legacy")
  H.write(base .. "/registry.json", vim.json.encode({
    schema_version = 0,
    projects = {
      { id = "legacy-id", name = "legacy", path = path },
    },
  }))

  registry._reset()
  local data = registry.load(true)
  H.eq(data.schema_version, 1)
  H.eq(data.projects["legacy-id"].name, "legacy")
  H.eq(data.order[1], "legacy-id")
  H.rmrf(base)
end)

H.test("newer schema versions are refused safely", function()
  local base = H.fresh()
  H.write(base .. "/registry.json", vim.json.encode({ schema_version = 99, projects = {} }))

  registry._reset()
  local data = registry.load(true)
  H.eq(vim.tbl_count(data.projects), 0)
  local backups = vim.fn.glob(base .. "/registry.json.corrupt-*", false, true)
  H.eq(#backups, 1)
  H.rmrf(base)
end)

H.test("missing project paths are detected and pruned without deleting files", function()
  local base, projects = H.fresh()
  local alive_path = make_project(projects, "alive")
  local dead_path = make_project(projects, "dead")
  H.ok(registry.register({ name = "alive", path = alive_path }))
  local dead = H.ok(registry.register({ name = "dead", path = dead_path }))
  H.rmrf(dead_path)

  local valid, missing = registry.check_paths()
  H.eq(#valid, 1)
  H.eq(#missing, 1)
  H.eq(missing[1].id, dead.id)

  local dry = registry.prune_missing(true)
  H.eq(#dry, 1)
  H.ok(registry.get(dead.id), "dry run must not remove metadata")

  local removed = registry.prune_missing(false)
  H.eq(#removed, 1)
  H.falsy(registry.get(dead.id))
  H.ok(fs.is_dir(alive_path), "pruning must never delete project files")
  H.rmrf(base)
end)
