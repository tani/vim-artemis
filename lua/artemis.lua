local M = {}

M.command = vim.command or vim.cmd
M.eval = vim.eval or vim.api.nvim_eval

M.cast = setmetatable({}, {
  __index = function(_, key)
    if key == 'dict' or key == 'list' or key == 'blob' then
      return vim[key] or function(x) return x end
    else
      throw('Invalid cast type: ' .. key)
    end
  end,
  __call = function(cast, t)
    if vim.fn.has('nvim') == 0 and type(t) == 'table' then
      local assocp = false
      for k, v in pairs(t) do
        assocp = assocp or type(k) ~= 'number'
        t[k] = cast(v)
      end
      return assocp and cast.dict(t) or cast.list(t)
    else
      return t
    end
  end
})

M.keymap = vim.keymap or {
  cmd = {},
  del = function(mode, lhs, ...)
    local args = {...}
    local opts = args[1] or {}
    for _, mode in pairs(type(mode) == 'table' and mode or { mode }) do
      local c = mode .. 'unmap'
      if opts.buffer then
        c = c .. ' <buffer> '
      end
      M.command(c .. ' ' .. lhs)
    end
  end,
  set = function(mode, lhs, rhs, ...)
    local args = {...}
    local opts = args[1] or {}
    for _, mode in pairs(type(mode) == 'table' and mode or { mode }) do
      local c = mode
      if not opts.remap or opts.noremap then
        c = c .. 'nore'
      end
      c = c .. 'map'
      for _, opt in pairs({ 'buffer', 'expr', 'nowait', 'silent', 'unique' }) do
        if opts[opt] then
          c = c .. ' <' .. opt .. '> '
        end
      end
      if type(lhs) == 'function' then
        keymap.cmd[lhs] = rhs
        c = c .. ' ' .. lhs .. ' ' .. 'lua require"artemis".keymap.cmd[ [=['..lhs..']=] ]()'
      else
        c = c .. ' ' .. lhs .. ' ' .. rhs
      end
      M.command(c)
    end
  end
}

local vars = setmetatable({}, {
  __index = function(_, scope)
    local prefix = scope == 'o' and '&' or (scope .. ':')
    return setmetatable({}, {
      __index = function(_, name)
        return M.eval(prefix .. name)
      end,
      __newindex = function(_, name, value)
        local str = vim.fn.string(M.cast(value))
        M.command('let ' .. prefix .. name .. ' = ' .. str)
      end
    })
  end
})
M.g = vim.g or vars.g
M.t = vim.t or vars.t
M.b = vim.b or vars.b
M.v = vim.v or vars.v
M.w = vim.w or vars.w
M.o = vim.o or vars.o
M.fn = vim.fn

return M