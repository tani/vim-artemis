local lc = require('artemis.core.luacompat')

local function run(src)
  local f = assert(loadstring(src))
  return f()
end

describe('goto continue rewriting', function()
  if rawget(_G, 'jit') then
    it('not needed on LuaJIT', function() end)
    return
  end
  local function rewritten(src)
    local out = lc.transform(src)
    assert(out, 'nothing rewritten')
    return run(out)
  end
  it('simple for continue', function()
    eq(rewritten([[
      local acc = {}
      for i = 1, 5 do
        if i % 2 == 0 then goto continue end
        acc[#acc + 1] = i
        ::continue::
      end
      return acc]]), { 1, 3, 5 })
  end)
  it('keeps real break', function()
    eq(rewritten([[
      local acc = {}
      for i = 1, 10 do
        if i == 2 then goto continue end
        if i == 5 then break end
        acc[#acc + 1] = i
        ::continue::
      end
      return acc]]), { 1, 3, 4 })
  end)
  it('while + nested loops with their own labels', function()
    eq(rewritten([[
      local acc, i = {}, 0
      while i < 3 do
        i = i + 1
        for j = 1, 3 do
          if j == 2 then goto continue end
          acc[#acc + 1] = i * 10 + j
          ::continue::
        end
        if i == 2 then goto continue end
        acc[#acc + 1] = -i
        ::continue::
      end
      return acc]]), { 11, 13, -1, 21, 23, 31, 33, -3 })
  end)
  it('ignores goto in strings and comments', function()
    eq(rewritten([[
      local s = "goto continue ::continue::" -- goto continue
      local n = 0
      for i = 1, 3 do
        if i == 1 then goto continue end
        n = n + i
        ::continue::
      end
      return n]]), 5)
  end)
  it('preserves line numbers', function()
    local src = 'for i=1,2 do\n if i==1 then goto continue end\n ::continue::\nend\nreturn debug.traceback()'
    local out = lc.transform(src)
    eq(select(2, out:gsub('\n', '\n')), select(2, src:gsub('\n', '\n')))
  end)
  it('require() of a file using goto', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. '/lua', 'p')
    local f = io.open(dir .. '/lua/artemis_goto_mod.lua', 'w')
    f:write('local M = {}\nfor i = 1, 4 do\n  if i % 2 == 1 then goto continue end\n  M[#M + 1] = i\n  ::continue::\nend\nreturn M\n')
    f:close()
    package.path = dir .. '/lua/?.lua;' .. package.path
    eq(require('artemis_goto_mod'), { 2, 4 })
  end)
end)

describe('lua 5.1 shims', function()
  if rawget(_G, 'jit') then
    return -- LuaJIT: shims are not installed
  end
  it('table.unpack / pack', function()
    eq({ table.unpack({ 1, 2, 3 }) }, { 1, 2, 3 })
    eq(table.pack(1, nil, 3).n, 3)
  end)
  it('load with string and env', function()
    local f = load('return x', 'chunk', 't', { x = 7 })
    eq(f(), 7)
  end)
  it('xpcall with arguments', function()
    local ok, res = xpcall(function(a, b) return a + b end, print, 2, 3)
    eq({ ok, res }, { true, 5 })
  end)
end)
