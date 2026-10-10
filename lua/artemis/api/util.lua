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

-- Vim refuses scoped variables whose names are not identifiers (e.g.
-- b:["nvim-autopairs"]); Neovim allows them through the API. Such keys are
-- kept in a Lua-side shadow table, keyed by scope ("g", "b:3", "w:1001", "t:1").
local shadow = {}
local function valid_name(name)
  return name:match('^[%a_][%w_]*$') ~= nil
end

--- Set `name` in the variable dictionary `dictref` (a g:/b:/w:/t: reference).
function M.setvar_dict(dictref, name, value, scope)
  if not valid_name(name) then
    shadow[scope] = shadow[scope] or {}
    shadow[scope][name] = { value }
    return
  end
  local d = vim.dict()
  d[name] = convert.to_vim(value)
  host.call('extend', dictref, d)
end

function M.delvar_dict(dictref, name, scope)
  if shadow[scope] and shadow[scope][name] then
    shadow[scope][name] = nil
    return
  end
  if host.call('has_key', dictref, name) == 1 then
    host.call('remove', dictref, name)
  end
end

--- Look a shadowed variable up; returns found, value.
function M.shadow_get(scope, name)
  local rec = shadow[scope] and shadow[scope][name]
  if rec then
    return true, rec[1]
  end
  return false
end

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

--- Is `w` a popup window (our emulation of floating windows)?
function M.is_popup(w)
  return type(w) == 'number' and w > 0 and F.win_id2win(w) == 0 and F.win_gettype(w) == 'popup'
end

--- Resolve a window handle (0 = current) and validate it.
function M.win(w)
  if w == nil or w == 0 then
    return F.win_getid()
  end
  if F.win_id2win(w) == 0 and not M.is_popup(w) then
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

--- Run `fn` in the context of `win` (works for popups, which cannot be
--- entered). Uses win_execute(), so no WinEnter/WinLeave autocmds fire.
function M.in_win(win, fn)
  if win == F.win_getid() then
    return fn()
  end
  local ok, res
  local id = require('artemis.core.registry').add(function()
    ok, res = pcall(fn)
  end)
  local called, err = pcall(F.win_execute, win, string.format('lua require("artemis.core.registry").call(%d)', id))
  require('artemis.core.registry').del(id)
  if not called then
    error(err, 0)
  end
  if ok == nil then
    error('Invalid window id: ' .. tostring(win), 2)
  end
  if not ok then
    error(res, 0)
  end
  return res
end

return M
