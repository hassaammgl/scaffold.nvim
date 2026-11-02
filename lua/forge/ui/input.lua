-- Native input helpers with validation loops.

local utils = require("forge.utils")

local M = {}

-- opts: { default, completion, prompt_extra }
function M.input(prompt, opts)
  opts = opts or {}
  local result = nil
  vim.ui.input({
    prompt = prompt,
    default = opts.default,
    completion = opts.completion,
  }, function(value)
    result = value
  end)
  return result
end

-- validate(value) -> ok, normalized_value_or_error
-- Re-prompts on invalid input; returns nil if the user cancels.
function M.validated(prompt, opts, validate)
  opts = opts or {}
  while true do
    local value = M.input(prompt, opts)
    if value == nil then
      return nil
    end
    if not validate then
      return value
    end
    local ok, normalized = validate(value)
    if ok then
      return normalized
    end
    utils.warn(tostring(normalized))
  end
end

function M.project_name(default)
  local validator = require("forge.core.validator")
  return M.validated("Project name: ", { default = default }, validator.project_name)
end

return M
