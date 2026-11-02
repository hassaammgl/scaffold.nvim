-- Filesystem helper tests.

local H = require("tests.harness")
local fs = require("forge.core.filesystem")

H.test("write refuses to overwrite by default", function()
  local base = vim.fn.tempname()
  H.mkdir(base)
  local path = base .. "/file.txt"

  local ok = fs.write(path, "first")
  H.ok(ok)
  H.eq(H.read(path), "first")

  local overwritten, err = fs.write(path, "second")
  H.falsy(overwritten)
  H.match(tostring(err), "refusing to overwrite")
  H.eq(H.read(path), "first")

  H.ok(fs.write(path, "second", { overwrite = true }))
  H.eq(H.read(path), "second")
  H.rmrf(base)
end)

H.test("atomic_write replaces content without leaving temp files", function()
  local base = vim.fn.tempname()
  H.mkdir(base)
  local path = base .. "/registry.json"

  H.ok(fs.atomic_write(path, '{"a":1}'))
  H.eq(H.read(path), '{"a":1}')
  H.ok(fs.atomic_write(path, '{"a":2}'))
  H.eq(H.read(path), '{"a":2}')

  local leftovers = vim.fn.glob(base .. "/*.tmp-*", false, true)
  H.eq(#leftovers, 0)
  H.rmrf(base)
end)

H.test("is_subpath handles roots and siblings", function()
  H.ok(fs.is_subpath("/a/b", "/a"))
  H.ok(fs.is_subpath("/a", "/a"))
  H.ok(fs.is_subpath("/a/b", "/"))
  H.falsy(fs.is_subpath("/a/bc", "/a/b"))
  H.falsy(fs.is_subpath("/b", "/a"))
  H.falsy(fs.is_subpath(nil, "/a"))
end)

H.test("remove_file refuses directories", function()
  local base = vim.fn.tempname()
  H.mkdir(base)
  local ok, err = fs.remove_file(base)
  H.falsy(ok)
  H.match(tostring(err), "refusing to remove directory")
  H.ok(fs.is_dir(base))
  H.rmrf(base)
end)
