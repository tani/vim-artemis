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

function M.cast(t)
  if vim.fn.has('nvim') > 0 or type(t) ~= 'table' then
    return t
  end
  local assocp = false
  for k, v in pairs(t) do
    assocp = assocp or type(k) ~= 'number'
    t[k] = M.cast(v)
  end
  return assocp and vim.dict(t) or vim.list(t)
end

M._augroup = {}
function M.create_augroup(name, ...)
  if vim.fn.has('nvim') > 0 then
    return vim.api.nvim_create_augroup(name, ...)
  end
  local id = generate_id()
  local opts = {}
  local args = {...}
  if #args > 0 then
    opts = args[1]
  end
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
  if opts.callback then
    if type(opts.callback) == 'function' then
      opts.command = 'lua require("artemis").autocmd[' .. id .. '].callback()'
    else
      opts.command = 'call ' .. opts.callback .. '()'
    end
  end
  if opts.buffer then
    opts.bufnr = opts.buffer
  end
  opts.event = event
  opts.cmd = opts.command
  M._autocmd[id] = opts
  return id
end

M._keymap = {}
local function keymap_del(mode, lhs, ...)
  local args = {...}
  local opts = args[1] or {}
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
local function keymap_set(mode, lhs, rhs, ...)
  local args = {...}
  local opts = args[1] or {}
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
      table.insert(args, 'lua require"artemis".keymap.cmd[ [=['..lhs..']=] ]()')
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
    local prefix = scope == 'o' and '&' or (scope .. ':')
    return setmetatable({}, {
      __index = function(_, name)
        return vim.eval(prefix .. name)
      end,
      __newindex = function(_, name, value)
        local str = vim.fn.string(M.cast(value))
        vim.command('let ' .. prefix .. name .. ' = ' .. str)
      end
    })
  end
})
M.g = vim.fn.has('nvim') > 0 and vim.g or vars.g
M.t = vim.fn.has('nvim') > 0 and vim.t or vars.t
M.b = vim.fn.has('nvim') > 0 and vim.b or vars.b
M.v = vim.fn.has('nvim') > 0 and vim.v or vars.v
M.w = vim.fn.has('nvim') > 0 and vim.w or vars.w
M.o = vim.fn.has('nvim') > 0 and vim.o or vars.o

local fn = setmetatable({}, {
  __index = function(_, name)
    return function(...)
      local str = ''
      for i, arg in ipairs({...}) do
        str = str .. (i > 1 and ', ' or '') .. vim.fn.string(M.cast(arg))
      end
      return M.eval('function("' .. name .. '")(' .. str .. ')')
    end
  end
})
M.fn = vim.fn.has('nvim') > 0 and vim.fn or fn

M.dict = vim.dict or function(x) return x end
M.list = vim.list or function(x) return x end
M.blob = vim.blob or function(x) return x end
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
