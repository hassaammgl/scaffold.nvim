-- Project detection tests.

local H = require("tests.harness")
local detector = require("forge.core.detector")

local function has_candidate(result, language, build_system)
  for _, candidate in ipairs(result.candidates or {}) do
    if candidate.language == language and (build_system == nil or candidate.build_system == build_system) then
      return true
    end
  end
  return false
end

H.test("CMake + C source is detected as C", function()
  local base = vim.fn.tempname()
  H.mkdir(base .. "/src")
  H.write(base .. "/CMakeLists.txt", "project(x C)\n")
  H.write(base .. "/src/main.c", "int main(void){return 0;}\n")

  local result = H.ok(detector.detect(base))
  H.eq(result.language, "c")
  H.eq(result.build_system, "cmake")
  H.ok(result.confidence >= 0.9)
  H.eq(result.root, require("forge.core.filesystem").normalize(base))
  H.rmrf(base)
end)

H.test("CMake + C++ source is detected as C++", function()
  local base = vim.fn.tempname()
  H.mkdir(base .. "/src")
  H.write(base .. "/CMakeLists.txt", "project(x CXX)\n")
  H.write(base .. "/src/main.cpp", "int main(){return 0;}\n")

  local result = H.ok(detector.detect(base))
  H.eq(result.language, "cpp")
  H.eq(result.build_system, "cmake")
  H.ok(has_candidate(result, "c"), "ambiguous C candidate should also be reported")
  H.rmrf(base)
end)

H.test("package.json + tsconfig.json is detected as TypeScript with npm", function()
  local base = vim.fn.tempname()
  H.mkdir(base)
  H.write(base .. "/package.json", '{"name":"x"}')
  H.write(base .. "/tsconfig.json", "{}")
  H.write(base .. "/package-lock.json", "{}")

  local result = H.ok(detector.detect(base))
  H.eq(result.language, "typescript")
  H.eq(result.build_system, "npm")
  H.ok(has_candidate(result, "javascript"))
  H.rmrf(base)
end)

H.test("Bun lockfile is detected", function()
  local base = vim.fn.tempname()
  H.mkdir(base)
  H.write(base .. "/package.json", "{}")
  H.write(base .. "/tsconfig.json", "{}")
  H.write(base .. "/bun.lock", "")

  local result = H.ok(detector.detect(base))
  H.ok(result.language == "typescript" or result.language == "bun")
  H.eq(result.build_system, "bun")
  H.ok(has_candidate(result, "bun", "bun"))
  H.rmrf(base)
end)

H.test("pom.xml and build.gradle map to Java build systems", function()
  local base = vim.fn.tempname()
  H.mkdir(base)
  H.write(base .. "/pom.xml", "<project/>")
  local maven = H.ok(detector.detect(base))
  H.eq(maven.language, "java")
  H.eq(maven.build_system, "maven")

  H.rmrf(base .. "/pom.xml")
  H.write(base .. "/build.gradle", "plugins {}")
  local gradle = H.ok(detector.detect(base))
  H.eq(gradle.language, "java")
  H.eq(gradle.build_system, "gradle")
  H.rmrf(base)
end)

H.test("monorepos report multiple candidates and the git root", function()
  local root = vim.fn.tempname()
  H.mkdir(root .. "/.git")
  H.write(root .. "/package.json", "{}")
  H.mkdir(root .. "/native")
  H.write(root .. "/native/CMakeLists.txt", "project(x CXX)\n")
  H.write(root .. "/native/main.cpp", "int main(){return 0;}\n")

  local result = H.ok(detector.detect(root .. "/native"))
  H.eq(result.vcs_root, require("forge.core.filesystem").normalize(root))
  H.ok(has_candidate(result, "cpp", "cmake"))
  H.ok(has_candidate(result, "javascript", "npm"))
  H.rmrf(root)
end)

H.test("empty directories produce no candidates", function()
  local base = vim.fn.tempname()
  H.mkdir(base)
  local result = H.ok(detector.detect(base))
  H.eq(#result.candidates, 0)
  H.eq(result.confidence, 0)
  H.falsy(result.best)
  H.rmrf(base)
end)

H.test("detect rejects missing paths", function()
  local result, err = detector.detect("/definitely/not/a/real/path/forge-test")
  H.falsy(result)
  H.ok(err ~= nil)
end)

H.test("detect_buffer falls back to cwd without error", function()
  local result = detector.detect_buffer(vim.api.nvim_get_current_buf())
  -- The result may be nil if cwd has no markers; either way it must not error.
  H.ok(result == nil or type(result) == "table")
end)
