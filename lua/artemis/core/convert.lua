-- L2: value conversion between Lua and Vim script.
--
--   to_vim(v)    Lua -> something Vim accepts as an argument
--   from_vim(v)  Vim value (userdata list/dict/funcref) -> plain Lua value
--
-- Known lossy spots on Vim: v:true/v:false come back as 1/0 and v:null as nil.
local host = require('artemis.core.host')

local M = {}

local NIL = vim.NIL
local function is_empty_dict(t)
  return vim._empty_dict_mt ~= nil and getmetatable(t) == vim._empty_dict_mt
end

local function is_list(t)
  if is_empty_dict(t) then
    return false
  end
  local n = 0
  for k in pairs(t) do
    if type(k) ~= 'number' or k < 1 or k % 1 ~= 0 then
      return false
    end
    n = n + 1
  end
  -- contiguous 1..n
  return n == #t
end

if host.kind == 'nvim' then
  -- Neovim converts tables natively; only vim.NIL / empty_dict need care.
  function M.to_vim(v)
    return v
  end
  function M.from_vim(v)
    return v
  end
  return M
end

local to_vim

to_vim = function(v, seen)
  local t = type(v)
  if t == 'table' then
    if v == NIL then
      return vim.eval('v:null')
    end
    seen = seen or {}
    if seen[v] then
      error('artemis: cannot convert a table with a cycle', 0)
    end
    seen[v] = true
    local out
    if is_list(v) and next(v) ~= nil then
      out = vim.list()
      for i = 1, #v do
        out:add(to_vim(v[i], seen))
      end
    else
      out = vim.dict()
      for k, x in pairs(v) do
        out[tostring(k)] = to_vim(x, seen)
      end
    end
    seen[v] = nil
    return out
  elseif t == 'boolean' then
    return v and 1 or 0
  end
  return v
end

local from_vim

from_vim = function(v)
  if type(v) ~= 'userdata' then
    return v
  end
  local kind = vim.type(v)
  if kind == 'list' then
    local out = {}
    for i = 1, #v do
      out[i] = from_vim(v[i])
    end
    return out
  elseif kind == 'dict' then
    local out = {}
    local keys = vim.call('keys', v)
    local n = #keys
    if n == 0 then
      return vim.empty_dict()
    end
    for i = 1, n do
      local k = keys[i]
      out[k] = from_vim(v[k])
    end
    return out
  elseif kind == 'funcref' then
    return function(...)
      local args = { ... }
      for i = 1, select('#', ...) do
        args[i] = to_vim(args[i])
      end
      local list = vim.list()
      for i = 1, select('#', ...) do
        list:add(args[i])
      end
      return from_vim(host.call('call', v, list))
    end
  end
  return v
end

M.to_vim = function(v)
  return to_vim(v)
end
M.from_vim = from_vim
M.is_list = is_list

return M
