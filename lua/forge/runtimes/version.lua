-- Version string parsing and comparison.

local M = {}

function M.extract(raw)
  if type(raw) ~= "string" then
    return nil
  end
  local version = raw:match("(%d+%.%d+%.%d+)")
    or raw:match("(%d+%.%d+)")
    or raw:match("(%d+)")
  return version
end

function M.parts(version)
  local parts = {}
  if type(version) ~= "string" then
    return parts
  end
  for number in version:gmatch("%d+") do
    parts[#parts + 1] = tonumber(number)
  end
  return parts
end

-- Returns -1, 0, or 1. Missing components compare as zero.
function M.compare(left, right)
  local a = M.parts(left)
  local b = M.parts(right)
  local count = math.max(#a, #b)
  for index = 1, count do
    local x = a[index] or 0
    local y = b[index] or 0
    if x < y then
      return -1
    elseif x > y then
      return 1
    end
  end
  return 0
end

function M.gte(left, right)
  return M.compare(left, right) >= 0
end

return M
