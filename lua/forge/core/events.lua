-- A tiny in-process event bus.
-- Handlers always run on the main loop via vim.schedule and errors are
-- isolated so a broken listener cannot break a Forge operation.

local M = {}

M._handlers = {}
M._next_id = 0

function M.on(event, handler)
  if type(event) ~= "string" or type(handler) ~= "function" then
    return nil, "event and handler are required"
  end
  M._next_id = M._next_id + 1
  local id = M._next_id
  M._handlers[event] = M._handlers[event] or {}
  M._handlers[event][id] = handler
  return id
end

function M.off(event, id)
  if M._handlers[event] then
    M._handlers[event][id] = nil
  end
end

function M.emit(event, payload)
  local handlers = {}
  for id, handler in pairs(M._handlers[event] or {}) do
    handlers[#handlers + 1] = { id = id, handler = handler }
  end
  if #handlers == 0 then
    return
  end
  table.sort(handlers, function(a, b)
    return a.id < b.id
  end)
  vim.schedule(function()
    for _, entry in ipairs(handlers) do
      local ok, err = pcall(entry.handler, payload)
      if not ok then
        require("forge.utils").warn(("Forge event handler for '%s' failed: %s"):format(event, tostring(err)))
      end
    end
  end)
end

function M.clear(event)
  if event then
    M._handlers[event] = nil
  else
    M._handlers = {}
  end
end

return M
