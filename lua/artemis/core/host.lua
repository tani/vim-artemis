-- L0: the only place that knows which editor we are running in.
-- Exposes the minimal primitives everything else is built on:
--   host.kind                'nvim' | 'vim'
--   host.eval(expr)          evaluate a Vim script expression (raw result)
--   host.exec(cmd)           run Ex command(s); raises on error; returns output
--   host.call(name, ...)     call a Vim function (raw args); raises on error
local M = {}

local native_fn = vim.fn
local has_nvim = native_fn.has('nvim')
M.kind = (has_nvim == 1 or has_nvim == true) and 'nvim' or 'vim'

if M.kind == 'nvim' then
  M.eval = vim.api.nvim_eval
  function M.exec(cmd)
    local out = vim.api.nvim_exec2(cmd, { output = true })
    return out.output
  end
  function M.call(name, ...)
    return vim.call(name, ...)
  end
else
  local vcall, veval = vim.call, vim.eval

  function M.eval(expr)
    local ok, res = pcall(veval, expr)
    if not ok then
      error('E15: Invalid expression: ' .. expr, 0)
    end
    return res
  end

  -- vim.command() and execute() swallow errors, so run the command through
  -- `:execute` inside a one-line :try and read the exception from a variable.
  -- (A multi-line try block would let `:command` etc. swallow the next lines.)
  local g = vim.g
  function M.exec(cmd)
    g.__artemis_cmd = cmd
    g.__artemis_exc = ''
    local out = vcall(
      'execute',
      'try | execute g:__artemis_cmd | catch | let g:__artemis_exc = v:exception | endtry'
    )
    local exc = g.__artemis_exc
    if exc ~= '' then
      error(exc, 0)
    end
    return (out:gsub('^\n', ''))
  end

  function M.call(name, ...)
    vcall('execute', 'let v:errmsg = ""')
    local res = { pcall(vcall, name, ...) }
    if not res[1] then
      local msg = veval('v:errmsg')
      if msg == '' then
        msg = tostring(res[2])
      end
      error(msg, 0)
    end
    return res[2]
  end
end

M.native_fn = native_fn

return M
