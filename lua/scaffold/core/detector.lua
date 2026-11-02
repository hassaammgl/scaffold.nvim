-- Project detection using marker files.
--
-- Detection is bounded (no recursive directory walk): it inspects the given
-- directory and at most a few parents, stopping at a Git root. Multiple
-- candidates are returned with confidence values because markers such as
-- Makefile are ambiguous and monorepos can contain several project types.

local fs = require("scaffold.core.filesystem")
local utils = require("scaffold.utils")

local M = {}

M.MARKERS = {
  { file = "CMakeLists.txt", candidates = { { language = "cpp", build_system = "cmake", confidence = 0.82 } } },
  { file = "compile_commands.json", candidates = { { language = "cpp", build_system = "cmake", confidence = 0.7 } } },
  { file = "Makefile", candidates = { { language = "c", build_system = "make", confidence = 0.4 } } },
  { file = "package.json", candidates = { { language = "javascript", build_system = "npm", confidence = 0.7 } } },
  { file = "tsconfig.json", candidates = { { language = "typescript", build_system = nil, confidence = 0.95 } } },
  { file = "bun.lock", candidates = { { language = "bun", build_system = "bun", confidence = 0.9 } } },
  { file = "bun.lockb", candidates = { { language = "bun", build_system = "bun", confidence = 0.9 } } },
  { file = "bunfig.toml", candidates = { { language = "bun", build_system = "bun", confidence = 0.8 } } },
  { file = "pyproject.toml", candidates = { { language = "python", build_system = "pip", confidence = 0.9 } } },
  { file = "requirements.txt", candidates = { { language = "python", build_system = "pip", confidence = 0.8 } } },
  { file = "setup.py", candidates = { { language = "python", build_system = "pip", confidence = 0.8 } } },
  { file = "setup.cfg", candidates = { { language = "python", build_system = "pip", confidence = 0.7 } } },
  { file = "pom.xml", candidates = { { language = "java", build_system = "maven", confidence = 0.95 } } },
  { file = "build.gradle", candidates = { { language = "java", build_system = "gradle", confidence = 0.95 } } },
  { file = "build.gradle.kts", candidates = { { language = "java", build_system = "gradle", confidence = 0.95 } } },
  { file = "settings.gradle", candidates = { { language = "java", build_system = "gradle", confidence = 0.8 } } },
  { file = "Cargo.toml", candidates = { { language = "rust", build_system = "cargo", confidence = 0.95 } } },
  { file = "go.mod", candidates = { { language = "go", build_system = "go", confidence = 0.95 } } },
}

local EXTENSION_LANGUAGES = {
  c = "c",
  h = "c",
  cpp = "cpp",
  cc = "cpp",
  cxx = "cpp",
  hpp = "cpp",
  hh = "cpp",
  hxx = "cpp",
  py = "python",
  ts = "typescript",
  tsx = "typescript",
  js = "javascript",
  jsx = "javascript",
  java = "java",
}

local function add_candidate(candidates, candidate, root, marker)
  local key = (candidate.language or "") .. "|" .. (candidate.build_system or "")
  local existing = candidates[key]
  if not existing or candidate.confidence > existing.confidence then
    candidates[key] = {
      language = candidate.language,
      build_system = candidate.build_system,
      confidence = candidate.confidence,
      marker = marker,
      root = root,
    }
  end
end

local function candidate_list(candidates)
  local list = {}
  for _, candidate in pairs(candidates) do
    list[#list + 1] = candidate
  end
  table.sort(list, function(a, b)
    if a.confidence == b.confidence then
      return (a.language or "") < (b.language or "")
    end
    return a.confidence > b.confidence
  end)
  return list
end

-- Count known source-file extensions in one directory. Only the project root
-- and its common source directories are inspected (never a recursive walk).
local function count_extensions(directory, extensions, depth)
  if depth > 1 then
    return
  end
  for _, entry in ipairs(fs.list_details(directory)) do
    if entry.type == "file" then
      local extension = entry.name:match("%.([%w_]+)$")
      if extension then
        extension = extension:lower()
        local language = EXTENSION_LANGUAGES[extension]
        if language then
          extensions[language] = (extensions[language] or 0) + 1
        end
      end
    end
  end
  if depth == 0 then
    for _, source_dir in ipairs({ "src", "source" }) do
      local child = fs.join(directory, source_dir)
      if fs.is_dir(child) then
        count_extensions(child, extensions, depth + 1)
      end
    end
  end
end

local function detect_dir(directory)
  local entries = fs.list_details(directory)
  if #entries == 0 then
    return {}, false
  end

  local names = {}
  local extensions = {}
  for _, entry in ipairs(entries) do
    names[entry.name] = entry
  end
  count_extensions(directory, extensions, 0)

  local candidates = {}
  local has_git = names[".git"] ~= nil

  for _, marker in ipairs(M.MARKERS) do
    if names[marker.file] then
      for _, candidate in ipairs(marker.candidates) do
        add_candidate(candidates, candidate, directory, marker.file)
      end
    end
  end

  -- C/C++ refinement: CMakeLists.txt and Makefile are shared by both.
  local has_cpp_sources = (extensions.cpp or 0) > 0
  local has_c_sources = (extensions.c or 0) > 0
  if names["CMakeLists.txt"] then
    if has_c_sources and not has_cpp_sources then
      add_candidate(candidates, { language = "c", build_system = "cmake", confidence = 0.92 }, directory, "CMakeLists.txt")
    elseif has_cpp_sources then
      add_candidate(candidates, { language = "cpp", build_system = "cmake", confidence = 0.92 }, directory, "CMakeLists.txt")
      add_candidate(candidates, { language = "c", build_system = "cmake", confidence = 0.35 }, directory, "CMakeLists.txt")
    else
      add_candidate(candidates, { language = "cpp", build_system = "cmake", confidence = 0.82 }, directory, "CMakeLists.txt")
      add_candidate(candidates, { language = "c", build_system = "cmake", confidence = 0.5 }, directory, "CMakeLists.txt")
    end
  end

  if names["Makefile"] then
    local base = 0.45
    if has_cpp_sources and not has_c_sources then
      add_candidate(candidates, { language = "cpp", build_system = "make", confidence = 0.8 }, directory, "Makefile")
    elseif has_c_sources and not has_cpp_sources then
      add_candidate(candidates, { language = "c", build_system = "make", confidence = 0.8 }, directory, "Makefile")
    else
      add_candidate(candidates, { language = "cpp", build_system = "make", confidence = base }, directory, "Makefile")
      add_candidate(candidates, { language = "c", build_system = "make", confidence = base }, directory, "Makefile")
    end
  end

  -- JavaScript/TypeScript refinement based on package metadata and lockfiles.
  if names["package.json"] then
    local package_manager = "npm"
    if names["bun.lock"] or names["bun.lockb"] then
      package_manager = "bun"
    elseif names["pnpm-lock.yaml"] then
      package_manager = "pnpm"
    elseif names["yarn.lock"] then
      package_manager = "yarn"
    elseif names["package-lock.json"] then
      package_manager = "npm"
    end

    if names["tsconfig.json"] then
      add_candidate(candidates, { language = "typescript", build_system = package_manager, confidence = 0.98 }, directory, "tsconfig.json")
      add_candidate(candidates, { language = "javascript", build_system = package_manager, confidence = 0.6 }, directory, "package.json")
    else
      add_candidate(candidates, { language = "javascript", build_system = package_manager, confidence = 0.9 }, directory, "package.json")
    end
    if package_manager == "bun" then
      add_candidate(candidates, { language = "bun", build_system = "bun", confidence = 0.85 }, directory, "bun.lock")
    end
  end

  return candidate_list(candidates), has_git
end

-- opts:
--   max_depth (default 6)
--   stop_at_git (default true)
function M.detect(path, opts)
  opts = opts or {}
  if type(path) ~= "string" or path == "" then
    return nil, "path is required"
  end
  local expanded = fs.expand(path)
  if fs.is_file(expanded) then
    expanded = fs.dirname(expanded)
  end
  if not fs.is_dir(expanded) then
    return nil, "not a directory: " .. expanded
  end

  local max_depth = opts.max_depth or 6
  local all = {}
  local seen = {}
  local vcs_root = nil
  local current = expanded
  local depth = 0

  while current and depth <= max_depth do
    local candidates, has_git = detect_dir(current)
    for _, candidate in ipairs(candidates) do
      local key = (candidate.language or "") .. "|" .. (candidate.build_system or "")
      if not seen[key] then
        seen[key] = true
        all[#all + 1] = candidate
      end
    end

    if has_git then
      vcs_root = current
      if opts.stop_at_git ~= false then
        break
      end
    end

    local parent = fs.dirname(current)
    if not parent or parent == current then
      break
    end
    current = parent
    depth = depth + 1
  end

  table.sort(all, function(a, b)
    if a.confidence == b.confidence then
      return a.root < b.root
    end
    return a.confidence > b.confidence
  end)

  return {
    path = expanded,
    root = all[1] and all[1].root or expanded,
    vcs_root = vcs_root,
    best = all[1],
    candidates = all,
    language = all[1] and all[1].language or nil,
    build_system = all[1] and all[1].build_system or nil,
    confidence = all[1] and all[1].confidence or 0,
  }
end

function M.is_project(path, opts)
  local result = M.detect(path, opts)
  return result ~= nil and #(result.candidates or {}) > 0
end

function M.find_root(path, opts)
  local result = M.detect(path, opts)
  return result and result.root or nil
end

function M.detect_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name and name ~= "" and not name:match("^%a+://") then
    return M.detect(name)
  end
  return M.detect(vim.uv.cwd())
end

function M.summary(result)
  if not result or not result.candidates or #result.candidates == 0 then
    return { "No project markers found." }
  end
  local lines = {
    ("Detection root: %s"):format(result.root),
    ("Confidence: %.0f%%"):format((result.confidence or 0) * 100),
    "",
    "Candidates:",
  }
  for _, candidate in ipairs(result.candidates) do
    lines[#lines + 1] = ("  %-12s %-8s %3.0f%%  %s"):format(
      candidate.language or "?",
      candidate.build_system or "-",
      (candidate.confidence or 0) * 100,
      utils.fmt_path and utils.fmt_path(candidate.root) or candidate.root
    )
  end
  if result.vcs_root then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Git root: " .. result.vcs_root
  end
  return lines
end

return M
