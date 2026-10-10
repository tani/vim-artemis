-- Behavioural plugin checks: run real key sequences and compare buffer text.
-- env: ARTEMIS_ROOT, SMOKE_PLUGINS, ARTEMIS_OUT
local root = os.getenv('ARTEMIS_ROOT')
package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path
require('artemis.inject').setup()
for d in (os.getenv('SMOKE_PLUGINS') or ''):gmatch('[^,]+') do
  package.path = d .. '/lua/?.lua;' .. d .. '/lua/?/init.lua;' .. package.path
  vim.cmd('set rtp+=' .. d)
end

local lines = {}
local function keys(s)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(s, true, false, true), 'x', false)
end
local function case(name, setup, text, input, expected, ft, col)
  local ok, err = xpcall(function()
    vim.cmd('enew!')
    vim.bo.expandtab = true; vim.bo.shiftwidth = 2
    if ft then vim.bo.filetype = ft; vim.bo.commentstring = '-- %s' end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, text)
    vim.api.nvim_win_set_cursor(0, { 1, col or 0 })
    setup()
    keys(input)
    local got = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    if not vim.deep_equal(got, expected) then
      error('expected ' .. vim.inspect(expected) .. ' got ' .. vim.inspect(got), 0)
    end
  end, debug.traceback)
  lines[#lines + 1] = (ok and 'ok   ' or 'FAIL ') .. name .. (ok and '' or ('\n  ' .. tostring(err):gsub('\n', '\n  ')))
end

local setup_done = {}
local function once(mod, cfg)
  return function()
    if not setup_done[mod] then
      setup_done[mod] = true
      require(mod).setup(cfg)
    end
  end
end

case('mini.comment gcc', once('mini.comment'), { 'local a = 1', 'local b = 2' }, 'gcc',
  { '-- local a = 1', 'local b = 2' }, 'lua')
case('mini.comment gc motion', once('mini.comment'), { 'a', 'b', 'c' }, 'gcj',
  { '-- a', '-- b', 'c' }, 'lua')
case('mini.surround saiw', once('mini.surround'), { 'hello world' }, 'saiw"',
  { '"hello" world' })
case('mini.surround sd', once('mini.surround'), { '"hello" world' }, 'sd"',
  { 'hello world' })
case('mini.surround sr', once('mini.surround'), { '(hello)' }, 'sr(]',
  { '[hello]' })
case('mini.pairs', once('mini.pairs'), { '' }, 'i(<Esc>',
  { '()' })
case('mini.move', once('mini.move'), { 'a', 'b' }, 'V<M-j><Esc>',
  { 'b', 'a' })
case('mini.splitjoin gS', once('mini.splitjoin'), { 'f(a, b)' }, 'gS',
  { 'f(', '  a,', '  b', ')' }, 'lua', 2)
case('mini.ai dib', once('mini.ai'), { 'x = foo(1, 2)', 'y' }, 'dib',
  { 'x = foo()', 'y' }, nil, 8)
case('mini.align ga', once('mini.align'), { 'a=1', 'bbb=2' }, 'gaip=',
  { 'a   = 1', 'bbb = 2' })
case('mini.trailspace', once('mini.trailspace'), { 'a   ', 'b' }, ':lua MiniTrailspace.trim()<CR>',
  { 'a', 'b' })
case('mini.operators gr', once('mini.operators'), { 'one two' }, 'yiwwgriw',
  { 'one one' })
case('mini.bracketed', once('mini.bracketed'), { 'a', 'b', 'c' }, ']l',
  { 'a', 'b', 'c' })

local f = assert(io.open(os.getenv('ARTEMIS_OUT'), 'w'))
f:write(table.concat(lines, '\n') .. '\n')
f:close()
