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

M.delete_command = function(name)
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
  opts = opts or {}
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
        vim.fn[callback](arg)
      end
      opts.cmd = 'lua require("artemis")._autocmd["' .. id .. '"]()'
    end
  end
  M.fn.autocmd_add({opts})
  return id
end

M._keymap = {}
local function keymap_del(modes, lhs, opts)
  opts = opts or {}
  for _, mode in pairs(type(modes) == 'table' and modes or { modes }) do
    local cmd = mode .. 'unmap'
    local args = {}
    if opts.buffer then
      table.insert(args, '<buffer>')
    end
    table.insert(args, lhs)
    M.cmd({cmd = cmd, args = args})
  end
end
local function keymap_set(modes, lhs, rhs, opts)
  opts = opts or {}
  for _, mode in pairs(type(modes) == 'table' and modes or { modes }) do
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

local function encode_opt(tbl)
  if type(tbl) == 'table' then
    if vim.tbl_islist(tbl) then
      return table.concat(tbl, ',')
    end
    local dict = {}
    for k, v in pairs(tbl) do
      if type(v) ~= 'string' then
        print('value of key ' .. k .. ' is not string')
        return ''
      end
      table.insert(dict, k .. ':' .. v)
    end
    return table.concat(dict, ',')
  else
    return string(tbl)
  end
end

local function decode_opt(str)
  if type(str) ~= 'string' then
    return str
  end
  if not str:match('[,:]') then
    return str
  end
  local tbl = vim.split(str, ',')
  local idx = 1
  local dict = {}
  for _, v in pairs(tbl) do
    local kv = vim.split(v, ':')
    if #kv == 1 then
      dict[idx] = kv[1]
      idx = idx + 1
    else
      dict[kv[1]] = kv[2]
    end
  end
  return dict
end

local function create_append(self, key)
  return function(new_value)
    local value = self[key]
    if type(value) ~= 'table' or type(new_value) ~= 'table' then
      print('value of key ' .. key .. ' is not table')
      return
    end
    if M.fn.empty(self[key]) then
      self[key] = new_value
    else
      -- merge value and new_value
      for k, v in pairs(new_value) do
        if type(k) == 'number' then
          table.insert(value, v)
        else
          value[k] = v
        end
      end
      self[key] = value
    end
    return self[key]
  end
end

local function create_prepend(self, key)
  return function(new_value)
    local value = self[key]
    if type(value) ~= 'table' or type(new_value) ~= 'table' then
      print('value of key ' .. key .. ' is not table')
      return
    end
    if M.fn.empty(self[key]) then
      self[key] = new_value
    else
      -- merge value and new_value
      for k, v in pairs(new_value) do
        if type(k) == 'number' then
          table.insert(value, 1, v)
        else
          value[k] = v
        end
      end
      self[key] = value
    end
    return self[key]
  end
end

local function create_remove(self, key)
  return function(new_value)
    local value = self[key]
    if type(value) ~= 'table' or type(new_value) ~= 'table' then
      print('value of key ' .. key .. ' is not table')
      return
    end
    if not M.fn.empty(self[key]) then
      local tbl = vim.split(value, ',')
      local new_tbl = {}
      for _, v in pairs(tbl) do
        if type(new_value) ~= 'table' then
          new_value = { new_value }
        end
        local found = false
        for _, nv in pairs(new_value) do
          if v == nv then
            found = true
            break
          end
        end
        if not found then
          table.insert(new_tbl, v)
        end
      end
      self[key] = table.concat(new_tbl, ',')
    end
    return self[key]
  end
end

local vars_o = setmetatable({}, {
  __index = function(_, name)
    return M.eval('&' .. name)
  end,
  __newindex = function(_, name, value)
    M.cmd('let &' .. name .. ' = ' .. M.fn.string(M.cast(value)))
  end
})

local vars_opt = setmetatable({}, {
  __index = function(self, name)
    local ret = decode_opt(M.eval('&' .. name))
    if type(ret) == 'table' then
      ret.append = create_append(self, name)
      ret.prepend = create_prepend(self, name)
      ret.remove = create_remove(self, name)
    end
    return ret
  end,
  __newindex = function(_, name, value)
    M.cmd('let &' .. name .. ' = ' .. M.fn.string(encode_opt(value)))
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

local vars_opt_local = setmetatable({}, {
  __index = function(self, name)
    local ret = decode_opt(M.eval('&l:' .. name))
    if type(ret) == 'table' then
      ret.append = create_append(self, name)
      ret.prepend = create_prepend(self, name)
      ret.remove = create_remove(self, name)
    end
    return ret
  end,
  __newindex = function(_, name, value)
    M.cmd('let &l:' .. name .. ' = ' .. M.fn.string(encode_opt(value)))
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

local vars_opt_global = setmetatable({}, {
  __index = function(self, name)
    local ret = decode_opt(M.eval('&g:' .. name))
    if type(ret) == 'table' then
      ret.append = create_append(self, name)
      ret.prepend = create_prepend(self, name)
      ret.remove = create_remove(self, name)
    end
    return ret
  end,
  __newindex = function(_, name, value)
    M.cmd('let &g:' .. name .. ' = ' .. M.fn.string(encode_opt(value)))
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

M.opt = vars_opt
M.opt_local = vars_opt_local
M.opt_global = vars_opt_global

M.fn = setmetatable({}, {
  __index = function(_, name)
    return setmetatable({name = name}, {
      __call = function(fn, ...)
        local args = {}
        for _, arg in ipairs({...}) do
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
