-- L2: callback registry. Maps a monotonically increasing id to a Lua
-- function so Vim script strings (autocmds, mappings, commands) can call back
-- into Lua without name collisions. Entries are released explicitly.
local M = {}

local entries = {}
local next_id = 0

function M.add(fn, owner)
  next_id = next_id + 1
  entries[next_id] = { fn = fn, owner = owner }
  return next_id
end

function M.get(id)
  local e = entries[id]
  return e and e.fn
end

function M.del(id)
  entries[id] = nil
end

--- Call entry `id`; used from generated Vim script as
--- `lua require("artemis.core.registry").call(ID, ...)`.
function M.call(id, ...)
  local fn = entries[id] and entries[id].fn
  if not fn then
    error('artemis: callback ' .. tostring(id) .. ' has been released', 0)
  end
  return fn(...)
end

function M.count()
  local n = 0
  for _ in pairs(entries) do
    n = n + 1
  end
  return n
end

return M
