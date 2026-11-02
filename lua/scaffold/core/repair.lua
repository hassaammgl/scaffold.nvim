-- Backfill editor/toolchain hints into C/C++ projects that were created before
-- compile_flags.txt + .clangd existed.
--
-- Reads the standard and include paths from the project itself (CMakeLists.txt
-- or Makefile), then writes the missing files. Existing files are never
-- overwritten, and nothing else in the project is touched.
--
-- Used by :ScaffoldRepair.

local editor = require("scaffold.templates.editor")
local fs = require("scaffold.core.filesystem")

local M = {}

local MAKEFILES = { "Makefile", "makefile", "GNUmakefile" }
local CPP_EXT = { cpp = true, cc = true, cxx = true, ixx = true, cppm = true, mpp = true }

---@param path string
---@return string?
local function read(path)
  local data = fs.read(path)
  return data
end

---@param text string
---@return string?
local function cmake_language(text)
  if text:match("%f[%w]LANGUAGES%f[%W][^)]*%f[%w]CXX%f[%W]") then
    return "cpp"
  end
  if text:match("%f[%w]LANGUAGES%f[%W][^)]*%f[%w]C%f[%W]") then
    return "c"
  end
  return nil
end

---@param text string
---@return string?
local function makefile_language(text)
  if text:match("%-std=c%+%+") or text:match("%f[%w]CXX%f[%W]") then
    return "cpp"
  end
  if text:match("%-std=c%d") or text:match("%f[%w]CC%f[%W]") then
    return "c"
  end
  return nil
end

---@param dir string
---@return { cpp: boolean, c: boolean }
local function scan_sources(dir)
  local found = { cpp = false, c = false }
  for _, candidate in ipairs({ dir, fs.join(dir, "src"), fs.join(dir, "source") }) do
    for _, entry in ipairs(fs.list_details(candidate)) do
      if entry.type == "file" then
        local ext = entry.name:match("%.([%w]+)$")
        if ext then
          if CPP_EXT[ext] then
            found.cpp = true
          elseif ext == "c" then
            found.c = true
          end
        end
      end
    end
  end
  return found
end

--- Work out language, standard and include dirs for a project directory.
---@param dir string
---@return table? project
---@return string? error
function M.detect(dir)
  dir = fs.expand(dir)
  if not fs.is_dir(dir) then
    return nil, "not a directory: " .. tostring(dir)
  end

  local cmake = read(fs.join(dir, "CMakeLists.txt"))
  local makefile
  for _, name in ipairs(MAKEFILES) do
    makefile = makefile or read(fs.join(dir, name))
  end

  local language = cmake and cmake_language(cmake) or nil
  if not language and makefile then
    language = makefile_language(makefile)
  end
  if not language then
    local sources = scan_sources(dir)
    if sources.cpp then
      language = "cpp"
    elseif sources.c then
      language = "c"
    end
  end

  if not language then
    return nil, "not a C/C++ project (no CMakeLists.txt, Makefile, or C/C++ sources in " .. dir .. ")"
  end

  local standard
  if cmake then
    local key = language == "c" and "CMAKE_C_STANDARD" or "CMAKE_CXX_STANDARD"
    standard = cmake:match("%f[%w]" .. key .. "%f[%W]%s+(%d+)")
    if not standard then
      standard = cmake:match("%f[%w]cxx_std_(%d+)%f[%W]") or cmake:match("%f[%w]c_std_(%d+)%f[%W]")
    end
  end
  if not standard and makefile then
    if language == "c" then
      standard = makefile:match("%-std=c(%d+)")
    else
      standard = makefile:match("%-std=c%+%+(%d+)")
    end
  end
  standard = standard or (language == "c" and "17" or "23")

  local includes = {}
  if fs.is_dir(fs.join(dir, "include")) then
    includes[1] = "include"
  end

  return {
    dir = dir,
    language = language,
    standard = standard,
    includes = includes,
  }
end

---@param project table result of M.detect
---@return { path: string, content: string }[]
local function files_for(project)
  local std = (project.language == "c" and "c" or "c++") .. project.standard
  local mode = project.language == "c" and "c-header" or "c++-header"
  return {
    { path = fs.join(project.dir, "compile_flags.txt"), content = editor.compile_flags(std, project.includes) },
    { path = fs.join(project.dir, ".clangd"), content = editor.clangd(std, mode) },
  }
end

---@param dir string
---@return table? plan
---@return string? error
function M.plan(dir)
  local project, err = M.detect(dir)
  if not project then
    return nil, err
  end
  return { project = project, files = files_for(project) }
end

--- Write the missing files. Returns a summary; never overwrites.
---@param dir string
---@return table? result
---@return string? error
function M.run(dir)
  local plan, err = M.plan(dir)
  if not plan then
    return nil, err
  end

  local result = {
    project = plan.project,
    created = {},
    kept = {},
    failed = {},
  }

  for _, file in ipairs(plan.files) do
    local name = fs.basename(file.path)
    if fs.exists(file.path) then
      result.kept[#result.kept + 1] = name
    else
      local ok, write_err = fs.write(file.path, file.content)
      if ok then
        result.created[#result.created + 1] = name
      else
        result.failed[#result.failed + 1] = ("%s (%s)"):format(name, tostring(write_err))
      end
    end
  end

  return result
end

return M
