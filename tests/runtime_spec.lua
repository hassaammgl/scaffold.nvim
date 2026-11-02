-- Runtime detection tests. These do not require language toolchains.

local H = require("tests.harness")
local runtimes = require("scaffold.runtimes")
local installer = require("scaffold.runtimes.installer")
local version = require("scaffold.runtimes.version")

H.test("version extraction and comparison", function()
  H.eq(version.extract("gcc (GCC) 13.2.1 20240301"), "13.2.1")
  H.eq(version.extract("cmake version 3.28.3"), "3.28.3")
  H.eq(version.extract('openjdk version "17.0.9"'), "17.0.9")
  H.eq(version.extract("v20"), "20")
  H.eq(version.extract("no version here"), nil)

  H.eq(version.compare("1.2.3", "1.2.3"), 0)
  H.eq(version.compare("1.2.4", "1.2.3"), 1)
  H.eq(version.compare("1.2", "1.2.0"), 0)
  H.eq(version.compare("2.0", "10.0"), -1)
  H.ok(version.gte("1.10.0", "1.9.9"))
end)

H.test("missing tools are reported without errors", function()
  local info, err = runtimes.info("scaffold-definitely-not-a-real-tool")
  H.ok(info, err)
  H.eq(info.found, false)
  H.falsy(info.version)
  H.eq(info.name, "scaffold-definitely-not-a-real-tool")

  H.falsy(runtimes.is_available("scaffold-definitely-not-a-real-tool"))
end)

H.test("installed tools include a path and version", function()
  local info = H.ok(runtimes.info("git"))
  H.eq(info.found, true)
  H.ok(info.path and info.path ~= "")
  H.ok(info.version ~= nil, "git --version should yield a version")
  H.match(info.raw, "git version")
end)

H.test("version results are cached and refreshable", function()
  runtimes.clear_cache()
  local first = H.ok(runtimes.info("git"))
  H.eq(first.cached, false)

  local second = H.ok(runtimes.info("git"))
  H.eq(second.cached, true)

  local refreshed = H.ok(runtimes.info("git", { refresh = true }))
  H.eq(refreshed.cached, false)

  local no_version = H.ok(runtimes.info("git", { refresh = true, version = false }))
  H.eq(no_version.found, true)
  H.falsy(no_version.version)
  H.falsy(no_version.raw)
end)

H.test("availability-only checks do not poison the version cache", function()
  runtimes.clear_cache()
  local no_version = H.ok(runtimes.info("git", { version = false }))
  H.falsy(no_version.version)
  H.eq(no_version.cached, false)

  local full = H.ok(runtimes.info("git"))
  H.eq(full.cached, false, "a version-less check must not populate the cache")
  H.ok(full.version ~= nil)
end)

H.test("toolchain status is produced without starting language servers", function()
  local toolchains = require("scaffold.toolchains")
  toolchains.load_builtins()
  local status, err = toolchains.status("cpp", { version = false })
  H.ok(status, err)
  H.eq(status.language, "cpp")
  H.ok(#status.groups >= 2)
  local found_any = false
  for _, group in ipairs(status.groups) do
    H.ok(type(group.name) == "string")
    for _, tool in ipairs(group.tools) do
      H.ok(type(tool.id) == "string")
      H.ok(type(tool.found) == "boolean")
      found_any = found_any or tool.found
    end
  end
  H.ok(found_any, "the current environment should report at least one installed C/C++ tool")
end)

H.test("install plans never execute anything and require explicit confirmation later", function()
  local plan = H.ok(installer.plan("scaffold-definitely-not-a-real-tool"))
  H.eq(plan.installed, false)
  H.falsy(plan.argv)
  H.ok(plan.reason ~= nil)
  H.falsy(installer.command_for("scaffold-definitely-not-a-real-tool"))

  local git_plan = H.ok(installer.plan("git"))
  H.eq(git_plan.installed, true)
  H.eq(git_plan.reason, "already installed")
end)

H.test("installer supports only pacman/apt and never AUR helpers", function()
  local manager, family = installer.manager()
  H.ok(manager == nil or manager == "pacman" or manager == "apt")
  if family then
    H.ok(family == "arch" or family == "debian")
  end

  local plan = installer.plan("scaffold-definitely-not-a-real-tool")
  if plan and plan.argv then
    for _, token in ipairs(plan.argv) do
      H.falsy(token:lower():find("yay", 1, true))
      H.falsy(token:lower():find("paru", 1, true))
    end
  end
end)
