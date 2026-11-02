-- Presentational helpers for Scaffold screens.

local utils = require("scaffold.utils")

local M = {}

function M.header(title, subtitle, width)
  width = width or 72
  local left = " " .. tostring(title or "Scaffold.nvim")
  local right = subtitle and (tostring(subtitle) .. " ") or ""
  local gap = math.max(1, width - #left - #right)
  return left .. string.rep(" ", gap) .. right
end

function M.rule(width, char)
  return string.rep(char or "─", width or 72)
end

function M.section(name)
  return " " .. tostring(name)
end

function M.item(label, detail, width)
  width = width or 72
  local left = "   " .. tostring(label or "")
  if not detail or detail == "" then
    return left
  end
  local padding = math.max(2, width - #left - #detail - 2)
  if padding <= 2 then
    return left .. "  " .. utils.truncate(detail, math.max(0, width - #left - 4))
  end
  return left .. string.rep(" ", padding) .. tostring(detail)
end

function M.status(found, version)
  if not found then
    return "missing"
  end
  if version and version ~= "" then
    return "ok (" .. version .. ")"
  end
  return "ok"
end

function M.kv(label, value, width)
  width = width or 72
  local left = " " .. utils.pad(label, 20)
  return left .. utils.truncate(tostring(value or ""), math.max(1, width - 22))
end

function M.bullet(text)
  return "  • " .. tostring(text)
end

function M.indent(text, amount)
  return string.rep(" ", amount or 2) .. tostring(text)
end

function M.highlights_for(lines, opts)
  opts = opts or {}
  local highlights = {}
  for index, line in ipairs(lines) do
    if opts.title_line and index == 1 then
      highlights[#highlights + 1] = { line = index, group = "ScaffoldTitle" }
    elseif opts.sections and opts.sections[line] then
      highlights[#highlights + 1] = { line = index, group = "ScaffoldSection" }
    elseif opts.muted and opts.muted[line] then
      highlights[#highlights + 1] = { line = index, group = "ScaffoldMuted" }
    end
  end
  return highlights
end

return M
