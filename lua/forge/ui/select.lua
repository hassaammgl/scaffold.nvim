-- Native selection helpers.
--
-- Uses vim.ui.select so user overrides (if any) keep working. Forge ships no
-- picker dependency and never forces a UI plugin.

local M = {}

local function default_format(item)
  if type(item) == "table" then
    return item.label or item.name or tostring(item)
  end
  return tostring(item)
end

-- opts: { format_item, kind, prompt_extra }
-- Returns the selected item (or nil on cancel).
function M.choose(prompt, choices, opts)
  opts = opts or {}
  choices = choices or {}
  if #choices == 0 then
    return nil
  end

  local result = nil
  vim.ui.select(choices, {
    prompt = prompt,
    kind = opts.kind,
    format_item = opts.format_item or default_format,
  }, function(choice)
    result = choice
  end)
  return result
end

-- Ordered yes/no confirmation. Defaults to "No" for safety.
function M.confirm(prompt, opts)
  opts = opts or {}
  local choices = opts.default == true and { "Yes", "No" } or { "No", "Yes" }
  local answer = M.choose(prompt, choices, {})
  return answer == "Yes"
end

function M.choose_strings(prompt, choices, opts)
  return M.choose(prompt, choices, opts)
end

return M
