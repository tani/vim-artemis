-- Lua 5.1 (PUC) compatibility for code written for LuaJIT/Neovim.
--
--   * missing standard functions: table.unpack/pack, load(string), xpcall(f, h, ...)
--   * `goto continue` / `::continue::` (LuaJIT, Lua >= 5.2) is rewritten at
--     require() time into Lua 5.1 code (see transform()).
--
-- Only applied when the running interpreter is not LuaJIT.
local M = {}

function M.shims()
  if rawget(_G, 'jit') then
    return
  end
  table.unpack = table.unpack or unpack
  table.pack = table.pack or function(...)
    return { n = select('#', ...), ... }
  end
  local plain_load = load
  _G.load = function(chunk, chunkname, mode, env)
    local f, err
    if type(chunk) == 'string' then
      f, err = loadstring(chunk, chunkname)
    else
      f, err = plain_load(chunk, chunkname)
    end
    if f and env then
      setfenv(f, env)
    end
    return f, err
  end
  local plain_xpcall = xpcall
  _G.xpcall = function(f, handler, ...)
    local n = select('#', ...)
    if n == 0 then
      return plain_xpcall(f, handler)
    end
    local args = { ... }
    return plain_xpcall(function()
      return f(unpack(args, 1, n))
    end, handler)
  end
end

--------------------------------------------------------------------- lexer
local function tokenize(src)
  local toks, i, n = {}, 1, #src
  local function add(kind, s, e)
    toks[#toks + 1] = { kind = kind, text = src:sub(s, e), start = s, stop = e }
  end
  while i <= n do
    local c = src:sub(i, i)
    if c:match('%s') then
      i = i + 1
    elseif src:sub(i, i + 1) == '--' then
      local lvl = src:match('^%-%-%[(=*)%[', i)
      if lvl then
        local close = ']' .. lvl .. ']'
        local _, e = src:find(close, i, true)
        i = (e or n) + 1
      else
        local e = src:find('\n', i, true)
        i = (e or n + 1) + 1
      end
    elseif c == '"' or c == "'" then
      local j = i + 1
      while j <= n do
        local d = src:sub(j, j)
        if d == '\\' then
          j = j + 2
        elseif d == c then
          break
        else
          j = j + 1
        end
      end
      add('string', i, j)
      i = j + 1
    elseif c == '[' and src:match('^%[=*%[', i) then
      local lvl = src:match('^%[(=*)%[', i)
      local close = ']' .. lvl .. ']'
      local _, e = src:find(close, i, true)
      add('string', i, e or n)
      i = (e or n) + 1
    elseif c:match('[%a_]') then
      local s, e = src:find('^[%w_]+', i)
      add('name', s, e)
      i = e + 1
    elseif c:match('%d') or (c == '.' and src:sub(i + 1, i + 1):match('%d')) then
      local j = i
      while j <= n do
        local d = src:sub(j, j)
        if d:match('[%w%.]') then
          j = j + 1
        elseif (d == '+' or d == '-') and src:sub(j - 1, j - 1):match('[eE]') and not src:sub(i, i + 1):match('^0[xX]') then
          j = j + 1
        else
          break
        end
      end
      add('number', i, j - 1)
      i = j
    elseif src:sub(i, i + 1) == '::' then
      add('sym', i, i + 1)
      i = i + 2
    else
      add('sym', i, i)
      i = i + 1
    end
  end
  return toks
end

---------------------------------------------------------------- transform
--- Rewrite the common "continue" idiom:
---   for/while ... do  <body>  ::label::  end
--- with `goto label` inside <body> (not crossing nested loops/functions) into
---   for/while ... do  repeat <body> until true  end
--- where `goto label` becomes `break`; real `break`s are propagated through a
--- flag. Line numbers are preserved (no newlines are added).
--- Returns the new source, or nil if nothing could be rewritten.
function M.transform(src)
  local toks = tokenize(src)
  local stack, edits, counter, changed = {}, {}, 0, false

  local function top()
    return stack[#stack]
  end
  local function nearest(kind_a, kind_b)
    for i = #stack, 1, -1 do
      local k = stack[i].kind
      if k == kind_a or k == kind_b then
        return stack[i]
      end
    end
  end

  local function finalize(loop, end_idx)
    if not loop.label or loop.label_idx + 3 ~= end_idx then
      return
    end
    local mine = {}
    for _, g in ipairs(loop.gotos) do
      if g.name == loop.label and not g.done then
        -- entries above `loop` in the snapshot must be plain blocks
        local ok, seen = true, false
        for _, e in ipairs(g.stack) do
          if seen and (e.kind == 'function' or e.kind == 'loop' or e.kind == 'repeat') then
            ok = false
          end
          if e == loop then
            seen = true
          end
        end
        if not ok then
          return
        end
        mine[#mine + 1] = g
      end
    end
    if #mine == 0 then
      return
    end
    counter = counter + 1
    local id = counter
    local flag = #loop.breaks > 0
    local flagname = '__artemis_b' .. id
    edits[#edits + 1] = {
      start = loop.body_start,
      stop = loop.body_start - 1,
      text = (flag and (' local ' .. flagname .. ' = false ') or ' ') .. 'repeat ',
    }
    for _, g in ipairs(mine) do
      g.done = true
      edits[#edits + 1] = { start = toks[g.tok].start, stop = toks[g.tok + 1].stop, text = 'do break end' }
    end
    for _, bidx in ipairs(loop.breaks) do
      edits[#edits + 1] = {
        start = toks[bidx].start,
        stop = toks[bidx].stop,
        text = 'do ' .. flagname .. ' = true break end',
      }
    end
    edits[#edits + 1] = {
      start = toks[loop.label_idx].start,
      stop = toks[loop.label_idx + 2].stop,
      text = ' until true ' .. (flag and ('if ' .. flagname .. ' then break end ') or ''),
    }
    changed = true
  end

  local i = 1
  while i <= #toks do
    local t = toks[i]
    if t.kind == 'name' then
      local v = t.text
      if v == 'function' then
        stack[#stack + 1] = { kind = 'function' }
      elseif v == 'if' then
        stack[#stack + 1] = { kind = 'if' }
      elseif v == 'for' or v == 'while' then
        stack[#stack + 1] = { kind = 'loop', await = true, breaks = {}, gotos = {} }
      elseif v == 'do' then
        local tp = top()
        if tp and tp.kind == 'loop' and tp.await then
          tp.await = false
          tp.body_start = t.stop + 1
        else
          stack[#stack + 1] = { kind = 'do' }
        end
      elseif v == 'repeat' then
        stack[#stack + 1] = { kind = 'repeat', breaks = {} }
      elseif v == 'end' then
        local e = table.remove(stack)
        if e and e.kind == 'loop' then
          finalize(e, i)
        end
      elseif v == 'until' then
        table.remove(stack)
      elseif v == 'break' then
        local lp = nearest('loop', 'repeat')
        if lp and lp.kind == 'loop' then
          lp.breaks[#lp.breaks + 1] = i
        end
      elseif v == 'goto' and toks[i + 1] and toks[i + 1].kind == 'name' then
        local snapshot = {}
        for k, e in ipairs(stack) do
          snapshot[k] = e
        end
        local g = { name = toks[i + 1].text, tok = i, stack = snapshot }
        for _, e in ipairs(stack) do
          if e.kind == 'loop' then
            e.gotos[#e.gotos + 1] = g
          end
        end
        i = i + 1
      end
    elseif t.kind == 'sym' and t.text == '::' and toks[i + 1] and toks[i + 1].kind == 'name'
      and toks[i + 2] and toks[i + 2].text == '::' then
      local tp = top()
      if tp and tp.kind == 'loop' and not tp.await then
        tp.label, tp.label_idx = toks[i + 1].text, i
      end
      i = i + 2
    end
    i = i + 1
  end

  if not changed then
    return nil
  end
  table.sort(edits, function(a, b)
    if a.start ~= b.start then
      return a.start > b.start
    end
    return (a.stop >= a.start) and not (b.stop >= b.start)
  end)
  local out = src
  for _, e in ipairs(edits) do
    out = out:sub(1, e.start - 1) .. e.text .. out:sub(e.stop + 1)
  end
  return out
end

------------------------------------------------------------------- loader
local function searchpath(name, path)
  local rel = name:gsub('%.', '/')
  for template in path:gmatch('[^;]+') do
    local f = template:gsub('%?', rel)
    local fh = io.open(f, 'rb')
    if fh then
      fh:close()
      return f
    end
  end
end

local function loader(name)
  local path = searchpath(name, package.path)
  if not path then
    return nil
  end
  local fh = io.open(path, 'rb')
  local src = fh:read('*a')
  fh:close()
  local chunk, err = loadstring(src, '@' .. path)
  if chunk then
    return chunk
  end
  local rewritten = M.transform(src)
  if rewritten then
    chunk = loadstring(rewritten, '@' .. path)
    if chunk then
      return chunk
    end
  end
  error("error loading module '" .. name .. "' from file '" .. path .. "':\n\t" .. tostring(err), 0)
end

function M.install()
  if rawget(_G, 'jit') or M._installed then
    return
  end
  M._installed = true
  M.shims()
  table.insert(package.loaders, 2, loader)
end

return M
