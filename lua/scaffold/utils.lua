-- Small, dependency-free helpers.
-- This module must not require any other Scaffold module (avoid cycles).

local M = {}

local notify_levels = vim.log and vim.log.levels or { INFO = 2, WARN = 3, ERROR = 4 }

function M.notify(message, level)
  level = level or notify_levels.INFO
  pcall(vim.notify, message, level, { title = "Scaffold.nvim" })
end

function M.warn(message)
  M.notify(message, notify_levels.WARN)
end

function M.error(message)
  M.notify(message, notify_levels.ERROR)
end

function M.trim(value)
  if type(value) ~= "string" then
    return value
  end
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.slugify(value)
  if type(value) ~= "string" then
    return "project"
  end
  local slug = value:lower()
  slug = slug:gsub("[^%w_%-%.]+", "-")
  slug = slug:gsub("%-+", "-")
  slug = slug:gsub("^[%-%.]+", "")
  slug = slug:gsub("[%-%.]+$", "")
  if slug == "" then
    return "project"
  end
  return slug
end

function M.starts_with(value, prefix)
  return type(value) == "string" and value:sub(1, #prefix) == prefix
end

function M.tbl_contains(list, needle)
  if type(list) ~= "table" then
    return false
  end
  for _, value in ipairs(list) do
    if value == needle then
      return true
    end
  end
  return false
end

function M.sorted_keys(map)
  local keys = {}
  for key in pairs(map or {}) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  return keys
end

local id_counter = 0

function M.uuid(seed)
  id_counter = id_counter + 1
  local base = tostring(seed or "scaffold"):gsub("%W+", "-")
  local random = math.random(0, 0xffffff)
  return string.format("%s-%x%04x-%x", base, os.time(), id_counter, random)
end

function M.now()
  return os.time()
end

function M.format_time(timestamp)
  if not timestamp or timestamp == 0 then
    return "never"
  end
  local ok, result = pcall(os.date, "%Y-%m-%d %H:%M", timestamp)
  if not ok or not result then
    return "unknown"
  end
  return result
end

-- Display helper only. Commands are always executed as argv arrays through
-- vim.system()/termopen(); nothing here is ever passed to a shell.
-- Compact "~/..." display form for paths.
function M.fmt_path(path)
  if type(path) ~= "string" or path == "" then
    return ""
  end
  local home = vim.fn.expand("~")
  if home ~= "" and path:sub(1, #home) == home then
    return "~" .. path:sub(#home + 1)
  end
  return path
end

function M.display_argv(argv)
  if type(argv) ~= "table" then
    return tostring(argv)
  end
  local parts = {}
  for i, value in ipairs(argv) do
    local escaped = value:gsub("([^%w%-%._/:=@])", "\\%1")
    parts[i] = escaped
  end
  return table.concat(parts, " ")
end

function M.is_list(value)
  if type(value) ~= "table" then
    return false
  end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return false
    end
    count = count + 1
  end
  if count == 0 then
    return true
  end
  for index = 1, count do
    if value[index] == nil then
      return false
    end
  end
  return true
end

function M.array_map(list, mapper)
  local result = {}
  for index, value in ipairs(list or {}) do
    result[index] = mapper(value, index)
  end
  return result
end

function M.truncate(value, width)
  value = tostring(value or "")
  if width <= 0 or #value <= width then
    return value
  end
  return value:sub(1, math.max(0, width - 1)) .. "…"
end

function M.pad(value, width)
  value = tostring(value or "")
  if #value >= width then
    return value
  end
  return value .. string.rep(" ", width - #value)
end

function M.deepcopy(value)
  return vim.deepcopy(value)
end

function M.deep_merge(base, overrides)
  local result = vim.deepcopy(base or {})
  for key, value in pairs(overrides or {}) do
    if type(value) == "table" and type(result[key]) == "table" and not M.is_list(value) then
      result[key] = M.deep_merge(result[key], value)
    else
      result[key] = vim.deepcopy(value)
    end
  end
  return result
end

return M
