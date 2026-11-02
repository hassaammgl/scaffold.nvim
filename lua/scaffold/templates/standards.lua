-- Minimum toolchain versions for the C and C++ standards the templates offer.
--
-- Checked before a project is created, so choosing "C++26" cannot silently
-- produce a project that no compiler on the machine can build (CMake also has
-- to know the value of CMAKE_<LANG>_STANDARD).
--
-- Versions come from `runtimes.info()`, which caches per tool for
-- `runtime_cache_ttl` seconds.

local runtimes = require("scaffold.runtimes")
local version = require("scaffold.runtimes.version")

local M = {}

--- compiler = { gcc, clang } minimums; cmake = first release that accepts the
--- standard in CMAKE_<LANG>_STANDARD.
local REQUIREMENTS = {
  cpp = {
    ["17"] = { gcc = "7.0", clang = "5.0", cmake = "3.8" },
    ["20"] = { gcc = "10.0", clang = "12.0", cmake = "3.12" },
    ["23"] = { gcc = "13.0", clang = "17.0", cmake = "3.20" },
    ["26"] = { gcc = "15.0", clang = "21.0", cmake = "3.30" },
  },
  c = {
    ["11"] = { gcc = "4.7", clang = "3.0", cmake = "3.1" },
    ["17"] = { gcc = "8.0", clang = "6.0", cmake = "3.8" },
    ["23"] = { gcc = "14.0", clang = "18.0", cmake = "3.21" },
  },
}

---@param runtime string?
---@return "gcc"|"clang"|nil
local function compiler_family(runtime)
  if type(runtime) ~= "string" then
    return nil
  end
  if runtime:match("clang") then
    return "clang"
  end
  if runtime:match("g%+%+") or runtime:match("^gcc") or runtime == "gcc" then
    return "gcc"
  end
  return nil
end

---@param tool string?
---@return table?
local function tool_info(tool)
  if type(tool) ~= "string" or tool == "" then
    return nil
  end
  local ok, result = pcall(runtimes.info, tool)
  if not ok or type(result) ~= "table" then
    return nil
  end
  return result
end

---@param language string?
---@return string?
local function normalize_language(language)
  if language == "cpp" or language == "c" then
    return language
  end
  return nil
end

---@param language string "c"|"cpp"
---@param standard string e.g. "26"
---@return string
local function label(language, standard)
  return (language == "c" and "C%s" or "C++%s"):format(standard)
end

--- Check a standard against the tools a project would use.
---@param ctx table renderer context: standard, language, runtime, build_system
---@return string? error a human readable reason, or nil when supported
function M.check(ctx)
  local language = normalize_language(ctx.language)
  if not language then
    return nil
  end
  local standard = tostring(ctx.standard or "")
  local need = REQUIREMENTS[language][standard]
  if not need then
    return nil
  end

  local fam = compiler_family(ctx.runtime)
  if fam then
    local info = tool_info(ctx.runtime)
    if info and info.found and info.version then
      local minimum = need[fam]
      if minimum and not version.gte(info.version, minimum) then
        return ("%s needs %s >= %s, but %s is %s. Pick a lower standard, upgrade %s, or choose another runtime.")
          :format(
            label(language, standard),
            fam == "gcc" and "GCC" or "Clang",
            minimum,
            ctx.runtime,
            info.version,
            ctx.runtime
          )
      end
    end
  end

  if ctx.build_system == "cmake" then
    local info = tool_info("cmake")
    if info and info.found and info.version and not version.gte(info.version, need.cmake) then
      return ("%s needs CMake >= %s, but cmake is %s. Pick a lower standard or upgrade CMake.")
        :format(label(language, standard), need.cmake, info.version)
    end
  end

  return nil
end

--- Highest standard in the matrix the given toolchain can handle.
---@param language string "c"|"cpp"
---@param runtime string? e.g. "g++"
---@param build_system string? e.g. "cmake"
---@return string? standard
function M.highest(language, runtime, build_system)
  local order = language == "c" and { "23", "17", "11" } or { "26", "23", "20", "17" }
  for _, standard in ipairs(order) do
    if not M.check({ language = language, standard = standard, runtime = runtime, build_system = build_system }) then
      return standard
    end
  end
  return nil
end

--- Versions of the tools relevant for C/C++, for :checkhealth.
---@return { gcc: table?, clang: table?, cmake: table? }
function M.versions()
  return {
    gcc = tool_info("g++"),
    clang = tool_info("clang++"),
    cmake = tool_info("cmake"),
  }
end

return M
