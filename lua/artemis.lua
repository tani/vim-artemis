------------------------------------- Artemis ----------------------------------
--Copyright (c) 2022-2023 TANIGUCHI Masaya
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

-- artemis v1 API, now a thin layer over the v2 emulation (see docs/design.md).
-- `require('artemis')` installs the Neovim `vim.*` API into Vim (idempotent)
-- and exposes the original `artemis.*` names for backward compatibility.
require('artemis.inject').setup()

local M = {}

M.create_command = function(name, callback, opts)
  return vim.api.nvim_create_user_command(name, callback, opts or {})
end

M.create_buf_command = function(bufn, name, callback, opts)
  return vim.api.nvim_buf_create_user_command(bufn, name, callback, opts or {})
end

M.delete_command = function(name)
  return vim.api.nvim_del_user_command(name)
end

M.create_augroup = function(name, opts)
  return vim.api.nvim_create_augroup(name, opts or {})
end

M.create_autocmd = function(event, opts)
  return vim.api.nvim_create_autocmd(event, opts)
end

M.keymap = vim.keymap

-- dict / list / blob / cast ---------------------------------------------------
M.dict = type(vim.dict) == 'function' and vim.dict or function(x) return x end
M.list = type(vim.list) == 'function' and vim.list or function(x) return x end
M.blob = type(vim.blob) == 'function' and vim.blob or function(x) return x end
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

-- variables -------------------------------------------------------------------
-- Unlike `vim.g`, artemis variables write nested assignments through:
--   artemis.g.lightline.colorscheme = 'x'
local function nested(root_get, root_set, path)
  return setmetatable({}, {
    __index = function(_, key)
      local value = path[1] == nil and root_get(key) or nil
      if path[1] ~= nil then
        value = root_get(path[1])
        for i = 2, #path do
          value = type(value) == 'table' and value[path[i]] or nil
        end
        value = type(value) == 'table' and value[key] or nil
      end
      if type(value) == 'table' then
        local p = { unpack(path) }
        p[#p + 1] = key
        if #path == 0 then
          p = { key }
        end
        return nested(root_get, root_set, p)
      end
      return value
    end,
    __newindex = function(_, key, value)
      if #path == 0 then
        root_set(key, value)
        return
      end
      local root = root_get(path[1])
      local node = root
      for i = 2, #path do
        node = node[path[i]]
      end
      node[key] = value
      root_set(path[1], root)
    end,
  })
end

local function var_scope(scope)
  return nested(function(k)
    return scope[k]
  end, function(k, v)
    scope[k] = v
  end, {})
end

M.g = var_scope(vim.g)
M.b = var_scope(vim.b)
M.w = var_scope(vim.w)
M.t = var_scope(vim.t)
M.v = var_scope(vim.v)

-- options ---------------------------------------------------------------------
M.o = vim.o
M.bo = vim.bo
M.go = vim.go
M.opt = vim.opt
M.opt_local = vim.opt_local
M.opt_global = vim.opt_global

-- functions / eval / cmd --------------------------------------------------------
-- fn proxies arguments via cast; dots chain into `#` (autoload names):
--   artemis.fn.lexima.add_rule { ... }  ==  vim.fn['lexima#add_rule']
local function fn_proxy(name)
  return setmetatable({}, {
    __call = function(_, ...)
      return vim.fn[name](...)
    end,
    __index = function(_, sub)
      return fn_proxy(name .. '#' .. sub)
    end,
  })
end
M.fn = setmetatable({}, {
  __index = function(_, name)
    return fn_proxy(name)
  end,
})

M.eval = function(expr)
  return vim.api.nvim_eval(expr)
end
M.cmd = vim.cmd

return M
