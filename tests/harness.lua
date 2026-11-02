-- Tiny zero-dependency test harness.

local H = {}

H.tests = {}
H.filter = os.getenv("SCAFFOLD_TEST_FILTER")

function H.test(name, fn)
  H.tests[#H.tests + 1] = { name = name, fn = fn }
end

function H.ok(value, message)
  if not value then
    error(message or "expected a truthy value", 2)
  end
  return value
end

function H.falsy(value, message)
  if value then
    error(message or ("expected a falsy value, got " .. vim.inspect(value)), 2)
  end
end

function H.eq(actual, expected, message)
  if not vim.deep_equal(actual, expected) then
    error(
      ("%s\nexpected: %s\nactual:   %s"):format(
        message or "values differ",
        vim.inspect(expected),
        vim.inspect(actual)
      ),
      2
    )
  end
end

function H.match(value, pattern, message)
  if type(value) ~= "string" or not value:find(pattern, 1, true) then
    error(("%s\nvalue: %s\nexpected substring: %s"):format(message or "substring not found", tostring(value), pattern), 2)
  end
end

function H.mkdir(path)
  local fs = require("scaffold.core.filesystem")
  local ok, err = fs.mkdirp(path)
  if not ok then
    error("could not create " .. tostring(path) .. ": " .. tostring(err), 2)
  end
end

function H.write(path, content)
  local fs = require("scaffold.core.filesystem")
  local ok, err = fs.write(path, content, { overwrite = true })
  if not ok then
    error("could not write " .. tostring(path) .. ": " .. tostring(err), 2)
  end
end

function H.read(path)
  local fs = require("scaffold.core.filesystem")
  local data, err = fs.read(path)
  if not data then
    error("could not read " .. tostring(path) .. ": " .. tostring(err), 2)
  end
  return data
end

function H.rmrf(path)
  if path and path ~= "" then
    pcall(vim.fn.delete, path, "rf")
  end
end

-- Fresh config with isolated registry/projects directories.
function H.fresh()
  local base = vim.fn.tempname()
  H.mkdir(base)
  local projects = base .. "/projects"
  H.mkdir(projects)
  local scaffold = require("scaffold")
  scaffold.setup({
    projects_dir = projects,
    registry_path = base .. "/registry.json",
    runtime_cache_ttl = 300,
    open_after_create = false,
    notify_on_exit = false,
  })
  require("scaffold.core.registry")._reset()
  require("scaffold.core.project")._reset_approvals()
  return base, projects
end

local counter = 0

function H.unique(prefix)
  counter = counter + 1
  return ("%s-%d-%d"):format(prefix or "t", os.time(), counter)
end

function H.run()
  local passed, failed = 0, 0
  print("Scaffold.nvim test suite")
  print(string.rep("-", 60))
  for _, case in ipairs(H.tests) do
    if not H.filter or case.name:find(H.filter, 1, true) then
      local ok, err = pcall(case.fn)
      if ok then
        passed = passed + 1
        print("  ok    " .. case.name)
      else
        failed = failed + 1
        print("  FAIL  " .. case.name)
        print("        " .. tostring(err):gsub("\n", "\n        "))
      end
    end
  end
  print(string.rep("-", 60))
  print(("%d passed, %d failed"):format(passed, failed))
  if failed > 0 then
    os.exit(1)
  end
end

return H
