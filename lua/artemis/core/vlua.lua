-- Emulation of Neovim's `v:lua` for Vim, which has no such thing.
--
--   v:lua.fn(args)      -> luaeval('require("artemis.core.vlua").call(path, _A)', [args])
--   &opfunc = v:lua.fn  -> a Funcref wrapping the Lua function (see funcref())
--
-- Both `Foo.bar.baz` global paths and `require'mod'.fn` / `require("mod").fn`
-- are supported, matching Neovim.
local M = {}

local function quote(s)
  return "'" .. s:gsub("'", "''") .. "'"
end

--- Resolve a v:lua path to a Lua function (or nil).
function M.resolve(path)
  local value
  if path:match("^require%s*[%('\"]") then
    local chunk = loadstring('return ' .. path)
    if not chunk then
      return nil
    end
    local ok, res = pcall(chunk)
    value = ok and res or nil
  else
    value = _G
    for part in path:gmatch('[^.]+') do
      if type(value) ~= 'table' then
        return nil
      end
      value = value[part]
    end
  end
  return value
end

--- Entry point used by generated luaeval() expressions.
function M.call(path, args)
  local fn = M.resolve(path)
  if type(fn) ~= 'function' and not (type(fn) == 'table' and getmetatable(fn) and getmetatable(fn).__call) then
    error('E5108: v:lua: function not found: ' .. path, 0)
  end
  local convert = require('artemis.core.convert')
  local list = convert.from_vim(args)
  local unpack = unpack or table.unpack
  return convert.to_vim(fn(unpack(list, 1, #list)))
end

-- Find the matching ')' for the '(' at `open`, skipping string literals.
local function match_paren(s, open)
  local depth, i = 0, open
  while i <= #s do
    local c = s:sub(i, i)
    if c == '(' then
      depth = depth + 1
    elseif c == ')' then
      depth = depth - 1
      if depth == 0 then
        return i
      end
    elseif c == "'" then
      i = i + 1
      while i <= #s do
        if s:sub(i, i) == "'" then
          if s:sub(i + 1, i + 1) == "'" then
            i = i + 1
          else
            break
          end
        end
        i = i + 1
      end
    elseif c == '"' then
      i = i + 1
      while i <= #s and s:sub(i, i) ~= '"' do
        if s:sub(i, i) == '\\' then
          i = i + 1
        end
        i = i + 1
      end
    end
    i = i + 1
  end
  return nil
end

--- Parse the path after `v:lua.` starting at `pos`; returns path, next_pos.
local function parse_path(s, pos)
  local rest = s:sub(pos)
  local req = rest:match("^require%s*%(%s*['\"][^'\"]+['\"]%s*%)") or rest:match("^require%s*['\"][^'\"]+['\"]")
  local i = pos
  local prefix = ''
  if req then
    prefix = req
    i = pos + #req
  end
  local tail = s:sub(i):match('^[%w_.]*')
  if req == nil and tail == '' then
    return nil
  end
  -- A trailing '.' is not part of the path.
  tail = tail:gsub('%.$', '')
  return prefix .. tail, i + #tail
end

--- Rewrite every `v:lua.path(args)` call in a Vim script string.
function M.rewrite(s)
  if type(s) ~= 'string' or not s:find('v:lua.', 1, true) then
    return s
  end
  local out, pos = {}, 1
  while true do
    local a, b = s:find('v:lua.', pos, true)
    if not a then
      break
    end
    out[#out + 1] = s:sub(pos, a - 1)
    local path, nxt = parse_path(s, b + 1)
    if path and s:sub(nxt, nxt) == '(' then
      local close = match_paren(s, nxt)
      if close then
        local args = s:sub(nxt + 1, close - 1)
        out[#out + 1] = string.format(
          "luaeval('require(\"artemis.core.vlua\").call(%s, _A)', [%s])",
          '"' .. path:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub("'", "''") .. '"',
          args
        )
        pos = close + 1
      else
        out[#out + 1] = s:sub(a, b)
        pos = b + 1
      end
    else
      out[#out + 1] = s:sub(a, b)
      pos = b + 1
    end
  end
  out[#out + 1] = s:sub(pos)
  return table.concat(out)
end

--- If `value` is exactly `v:lua.path`, return a Lua closure that calls it.
function M.as_function(value)
  if type(value) ~= 'string' then
    return nil
  end
  local path = value:match('^v:lua%.(.+)$')
  if not path then
    return nil
  end
  return function(...)
    local fn = M.resolve(path)
    if type(fn) ~= 'function' then
      error('E5108: v:lua: function not found: ' .. path, 0)
    end
    return fn(...)
  end
end

return M
