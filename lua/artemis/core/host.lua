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
  local vlua = require('artemis.core.vlua')
  local g = vim.g

  -- All Vim-level calls go through a helper that catches errors *inside*
  -- Vim and returns them as data. Letting an error escape into Lua leaves a
  -- pending exception behind when an outer :try is active, which would break
  -- `pcall(vim.fn.xxx)` in plugins (and print a message).
  vcall(
    'execute',
    table.concat({
      'function! ArtemisCall(name, args) abort',
      '  try',
      '    return [0, call(a:name, a:args)]',
      '  catch',
      '    return [1, substitute(v:exception, "^Vim\\%((\\w\\+)\\)\\=:", "", "")]',
      '  endtry',
      'endfunction',
    }, '\n')
  )

  -- Vim job/channel objects cannot be represented in Lua; keep them on the
  -- Vim side and hand out numeric ids instead.
  vcall(
    'execute',
    table.concat({
      'let g:ArtemisObjs = {}',
      'let g:ArtemisNext = 0',
      'function! ArtemisJobStart(cmd, opts) abort',
      '  let l:job = job_start(a:cmd, a:opts)',
      '  let g:ArtemisNext += 1',
      '  let g:ArtemisObjs[g:ArtemisNext] = {"job": l:job, "chan": job_getchannel(l:job)}',
      '  return g:ArtemisNext',
      'endfunction',
      'function! ArtemisJobStatus(id) abort',
      '  return has_key(g:ArtemisObjs, a:id) ? job_status(g:ArtemisObjs[a:id].job) : "dead"',
      'endfunction',
      'function! ArtemisJobStop(id, ...) abort',
      '  return has_key(g:ArtemisObjs, a:id) ? call("job_stop", [g:ArtemisObjs[a:id].job] + a:000) : 0',
      'endfunction',
      'function! ArtemisJobInfo(id) abort',
      '  return has_key(g:ArtemisObjs, a:id) ? job_info(g:ArtemisObjs[a:id].job) : {}',
      'endfunction',
      'function! ArtemisChanSend(id, data) abort',
      '  call ch_sendraw(g:ArtemisObjs[a:id].chan, a:data)',
      'endfunction',
      'function! ArtemisChanCloseIn(id) abort',
      '  call ch_close_in(g:ArtemisObjs[a:id].chan)',
      'endfunction',
      -- hot paths: one round trip instead of several
      'function! ArtemisGetLines(buf, s, e, strict) abort',
      '  let l:b = a:buf == 0 ? bufnr("%") : a:buf',
      '  if !bufexists(l:b) | throw "Invalid buffer id: " . a:buf | endif',
      '  let l:n = l:b == bufnr("%") ? line("$") : get(getbufinfo(l:b), 0, {"linecount": 0}).linecount',
      '  let l:s = a:s < 0 ? l:n + a:s + 1 : a:s',
      '  let l:e = a:e < 0 ? l:n + a:e + 1 : a:e',
      '  if a:strict && (l:s < 0 || l:s > l:n || l:e < 0 || l:e > l:n) | throw "Index out of bounds" | endif',
      '  let l:s = max([0, min([l:s, l:n])])',
      '  let l:e = max([0, min([l:e, l:n])])',
      '  if a:strict && l:e < l:s | throw "\'start\' is higher than \'end\'" | endif',
      '  return l:s >= l:e ? [] : getbufline(l:b, l:s + 1, l:e)',
      'endfunction',
      'function! ArtemisCursor(win) abort',
      '  let l:w = a:win == 0 ? win_getid() : a:win',
      '  if empty(getwininfo(l:w)) | throw "Invalid window id: " . a:win | endif',
      '  return [line(".", l:w), col(".", l:w) - 1]',
      'endfunction',
      'function! ArtemisJobRelease(id) abort',
      '  call remove(g:ArtemisObjs, a:id)',
      'endfunction',
    }, '\n')
  )

  function M.call(name, ...)
    local n = select('#', ...)
    local args = { ... }
    if n > 0 and (name == 'eval' or name == 'execute') then
      args[1] = vlua.rewrite(args[1])
    end
    local list = vim.list()
    for i = 1, n do
      list:add(args[i])
    end
    local r = vcall('ArtemisCall', name, list)
    if r[1] ~= 0 then
      error(r[2], 0)
    end
    return r[2]
  end

  function M.eval(expr)
    return M.call('eval', expr)
  end

  -- `:execute` inside a one-line :try; the exception text is read back from
  -- a variable. (A multi-line try block would let `:command` etc. swallow the
  -- following lines.) Runs at global scope so plain `:let x` stays global.
  function M.exec(cmd)
    g.__artemis_cmd = vlua.rewrite(cmd)
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
end

--- Call a Vim function with an explicit argument count (nil -> v:null).
function M.call_args(name, n, args)
  local unpack = unpack or table.unpack
  return M.call(name, unpack(args, 1, n))
end

M.native_fn = native_fn

return M
