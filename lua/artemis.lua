------------------------------------- Artemis ----------------------------------
--Copyright (c) 2022 TANIGUCHI Masaya
--
--Permission is hereby granted, free of charge, to any person obtaining a copy
--of this software and associated documentation files (the "Software"), to deal
--in the Software without restriction, including without limitation the rights
--to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--copies of the Software, and to permit persons to whom the Software is
--furnished to do so, subject to the following conditions:
--
--The above copyright notice and this permission notice shall be included in all
--copies or substantial portions of the Software.
--
--THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
--SOFTWARE.
--------------------------------------------------------------------------------

local M = {}

local function generate_id()
  return string.format('%02x', math.floor(os.clock() * 1000000))
end

M._command = {}
M.create_command = function(name, callback, opts)
  if vim.fn.has('nvim') > 0 then
    return vim.api.nvim_create_user_command(name, callback, opts)
  end
  local _callback = callback
  if type(callback) == 'function' then
    M._command[name] = callback
    _callback = 'lua require("artemis")._command["' .. name .. '"]({reg = [=[<reg>]=], bang = [=[<bang>]=] == "!", args = [=[<args>]=], fargs = {<f-args>}, line1 = <line1>, line2 = <line2>, count = <count>, range = <range>, mods = [=[<mods>]=]})'
  end
  local args = {}
  for k, v in pairs(opts) do
    if k == 'force' then
      goto continue
    end
    if type(v) == 'boolean' then
      if v then
        table.insert(args, '-' .. k)
      end
    end
    if type(v) == 'string' then
      table.insert(args, '-' .. k .. '=' .. v)
    end
    ::continue::
  end
  table.insert(args, name)
  table.insert(args, _callback)
  M.cmd.command { bang = opts.force, args = args }
end

M.delete_command = function()
  if vim.fn.has('nvim') > 0 then
    return vim.api.nvim_del_user_command(name)
  end
  M.cmd.delcommand(name)
end

M.dict = vim.dict or function(x) return x end
M.list = vim.list or function(x) return x end
M.blob = vim.blob or function(x) return x end
function M.cast(t)
  if type(t) ~= 'table' then
    return t
  end
  local assocp = false
  for k, v in pairs(t) do
    assocp = assocp or type(k) ~= 'number'
    t[k] = M.cast(v)
  end
  return assocp and M.dict(t) or M.list(t)
end

M._augroup = {}
function M.create_augroup(name, opts)
  if vim.fn.has('nvim') > 0 then
    return vim.api.nvim_create_augroup(name, opts) 
  end
  local id = generate_id()
  local opts = opts or {}
  if opts.clear then
    vim.command('augroup ' .. name .. ' | autocmd! | augroup END')
  else
    vim.command('augroup ' .. name .. ' | augroup END')
  end
  M._augroup[id] = name
  return id
end

M._autocmd = {}
function M.create_autocmd(event, opts)
  if vim.fn.has('nvim') > 0 then
    return vim.api.nvim_create_autocmd(event, opts)
  end
  local id = generate_id()
  if type(opts.group) == 'number' then
    opts.group = M._augroup[opts.group]
  end
  if opts.buffer then
    opts.bufnr = opts.buffer
  end
  opts.event = event
  opts.cmd = opts.command
  if opts.callback then
    local callback = opts.callback
    opts.callback = nil
    if type(callback) == 'function' then
      M._autocmd[id] = function()
        local arg = {
          id = id,
          event = opts.event,
          group = opts.group,
          buf = vim.fn.expand('<abuf>'),
          file = vim.fn.expand('<afile>'),
          match = vim.fn.expand('<amatch>'),
        }
        callback(arg)
      end
      opts.cmd = 'lua require("artemis")._autocmd["' .. id .. '"]()'
    else
      M._autocmd[id] = function()
        local arg = {
          id = id,
          event = opts.event,
          group = opts.group,
          buf = vim.fn.expand('<abuf>'),
          file = vim.fn.expand('<afile>'),
          match = vim.fn.expand('<amatch>'),
        }
        vim.fn[callback](opts.arg)
      end
      opts.cmd = 'lua require("artemis")._autocmd["' .. id .. '"]()'
    end
  end
  M.fn.autocmd_add({opts})
  return id
end

M._keymap = {}
local function keymap_del(mode, lhs, opts)
  local opts = opts or {}
  for _, mode in pairs(type(mode) == 'table' and mode or { mode }) do
    local cmd = mode .. 'unmap'
    local args = {}
    if opts.buffer then
      table.insert(args, '<buffer>')
    end
    table.insert(args, lhs)
    M.cmd({cmd = cmd, args = args})
  end
end
local function keymap_set(mode, lhs, rhs, opts) 
  local opts = opts or {}
  for _, mode in pairs(type(mode) == 'table' and mode or { mode }) do
    local cmd = mode
    if not opts.remap or opts.noremap then
      cmd = cmd .. 'nore'
    end
    cmd = cmd .. 'map'
    local args = {}
    for _, opt in pairs({ 'buffer', 'expr', 'nowait', 'silent', 'unique' }) do
      if opts[opt] then
        table.insert(args, '<' .. opt .. '>')
      end
    end
    table.insert(args, lhs)
    if type(lhs) == 'function' then
      M._keymap[lhs] = rhs
      table.insert(args, 'lua require"artemis"._keymap[ [=['..lhs..']=] ]()')
    else
      table.insert(args, rhs)
    end
    M.cmd({cmd = cmd, args = args})
  end
end
M.keymap = vim.keymap or {
  del = keymap_del,
  set = keymap_set
}

local vars = setmetatable({}, {
  __index = function(_, scope)
    return setmetatable({__name = ''}, {
      __newindex = function(var, name, value)
        M.cmd( 'let ' .. scope .. ':' .. var.__name .. '["' .. name .. '"]' .. ' = ' .. vim.fn.string(M.cast(value)) )
      end,
      __index = function(var, name)
        local val = M.eval(scope .. ':' .. var.__name .. '["' .. name .. '"]')
        if type(val) == 'table' then
          val.__name = var.__name .. '["' .. name .. '"]'
          setmetatable(val, getmetatable(var))
        end
        return val
      end
    })
  end
})

local vars_o = setmetatable({}, {
  __index = function(_, name)
    return M.eval('&' .. name)
  end,
  __newindex = function(_, name, value)
    M.cmd('let &' .. name .. ' = ' .. M.fn.string(M.cast(value)))
  end
})
local vars_bo = setmetatable({}, {
  __index = function(_, name)
    return M.eval('&l:' .. name)
  end,
  __newindex = function(_, name, value)
    M.cmd('let &l:' .. name .. ' = ' .. M.fn.string(value))
  end
})
local vars_go = setmetatable({}, {
  __index = function(_, name)
    return M.eval('&g:' .. name)
  end,
  __newindex = function(_, name, value)
    M.cmd('let &g:' .. name.. ' = ' .. M.fn.string(value))
  end
})

M.g = vars.g
M.t = vars.t
M.b = vars.b
M.v = vars.v
M.w = vars.w
M.o = vars_o
M.bo = vars_bo
M.go = vars_go

M.fn = setmetatable({}, {
  __index = function(_, name)
    return setmetatable({name = name}, {
      __call = function(fn, ...)
        local args = {}
        for i, arg in ipairs({...}) do
          table.insert(args, M.cast(arg))
        end
        local unpack = unpack or table.unpack
        return vim.fn[fn.name](unpack(args))
      end,
      __index = function(fn, subname)
        return setmetatable(
          { name = fn.name .. '#' .. subname },
          getmetatable(fn)
        )
      end
    })
  end
})

M.eval = vim.eval or vim.api.nvim_eval
M.cmd = vim.cmd or setmetatable({}, {
  __call = function(cmd, t) 
    if type(t) == 'table' then
      local c = t.cmd or t[1]
      if t.bang then
        c = c .. '!'
      end
      for i, arg in ipairs(t) do
        if i > 1 then
          c = c .. ' ' .. arg
        end
      end
      for _, arg in pairs(t.args or {}) do
        c = c .. ' ' .. arg
      end
      return cmd(c)
    end
    return vim.command(t)
  end,
  __index = function(cmd, name)
    return function(t)
      if type(t) == 'table' then
        local u = { cmd = name }
        for k, v in pairs(t) do
          u[k] = v
        end
        return cmd(u)
      end
      return vim.command(name .. ' ' .. t)
    end
  end
})

return M
