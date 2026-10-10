-- Shared helpers for the vim.api emulation (Vim host only).
local host = require('artemis.core.host')
local convert = require('artemis.core.convert')

local M = {}

--- F.name(...) calls Vim function `name`, converting args and results.
M.F = setmetatable({}, {
  __index = function(t, name)
    local f = function(...)
      local args = { ... }
      local n = select('#', ...)
      for i = 1, n do
        args[i] = convert.to_vim(args[i])
      end
      return convert.from_vim(host.call_args(name, n, args))
    end
    rawset(t, name, f)
    return f
  end,
})
local F = M.F

function M.vstr(s)
  return "'" .. tostring(s):gsub("'", "''") .. "'"
end

function M.err(fmt, ...)
  error(string.format(fmt, ...), 3)
end

local function truthy(x)
  return x == 1 or x == true
end
M.truthy = truthy

--- Resolve a buffer handle (0 = current) and validate it.
function M.buf(b)
  if b == nil or b == 0 then
    return F.bufnr('%')
  end
  if not truthy(F.bufexists(b)) then
    error('Invalid buffer id: ' .. tostring(b), 3)
  end
  return b
end

--- Resolve a window handle (0 = current) and validate it.
function M.win(w)
  if w == nil or w == 0 then
    return F.win_getid()
  end
  if F.win_id2win(w) == 0 then
    error('Invalid window id: ' .. tostring(w), 3)
  end
  return w
end

function M.tab(t)
  if t == nil or t == 0 then
    return F.tabpagenr()
  end
  if t < 1 or t > F.tabpagenr('$') then
    error('Invalid tabpage id: ' .. tostring(t), 3)
  end
  return t
end

function M.linecount(b)
  return host.eval(string.format('get(getbufinfo(%d), 0, {"linecount": 0}).linecount', b))
end

--- Neovim index normalisation: 0-based, end-exclusive; negative indices
--- count from n + 1 (so -1 is "past the end").
function M.norm_range(s, e, n, strict)
  if s < 0 then
    s = n + s + 1
  end
  if e < 0 then
    e = n + e + 1
  end
  if strict then
    if s < 0 or s > n or e < 0 or e > n then
      error('Index out of bounds', 3)
    end
  else
    s = math.max(0, math.min(s, n))
    e = math.max(0, math.min(e, n))
  end
  if e < s then
    if strict then
      error("'start' is higher than 'end'", 3)
    end
    e = s
  end
  return s, e
end

--- Run `fn` with `win` as the current window (restoring afterwards).
function M.in_win(win, fn)
  local cur = F.win_getid()
  if win == cur then
    return fn()
  end
  host.exec('noautocmd call win_gotoid(' .. win .. ')')
  local ok, res = pcall(fn)
  if F.win_id2win(cur) ~= 0 then
    host.exec('noautocmd call win_gotoid(' .. cur .. ')')
  end
  if not ok then
    error(res, 0)
  end
  return res
end

return M
