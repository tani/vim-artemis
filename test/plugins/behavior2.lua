-- Differential checks: records the buffer after each action; compare.sh diffs
-- the Neovim run (oracle) against the Vim run.
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
local function case(name, setup, text, input, expected, col)
  local ok, err = xpcall(function()
    vim.cmd('enew!')
    vim.bo.expandtab = true
    vim.bo.shiftwidth = 2
    vim.bo.commentstring = '-- %s'
    vim.api.nvim_buf_set_lines(0, 0, -1, false, text)
    vim.api.nvim_win_set_cursor(0, { 1, col or 0 })
    setup()
    keys(input)
    local got = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    lines[#lines + 1] = name .. ' => ' .. vim.inspect(got, { newline = ' ', indent = '' })
  end, debug.traceback)
  if not ok then
    lines[#lines + 1] = name .. ' => ERROR ' .. tostring(err):gsub('\n.*', '')
  end
end
local done = {}
local function once(key, fn)
  return function()
    if not done[key] then done[key] = true; fn() end
  end
end

local comment = once('comment', function() require('Comment').setup() end)
local function call(fn)
  return function() fn() end
end
-- (key sequences for gcc/ys need operator-pending timing the headless harness
-- cannot reproduce even on Neovim, so drive the plugins through their API)
case('Comment.nvim toggle.linewise.current', comment, { 'a', 'b' }, ':lua require("Comment.api").toggle.linewise.current()<CR>', { '-- a', 'b' })
case('Comment.nvim comment/uncomment', comment, { 'a', 'b' },
  ':lua local api = require("Comment.api"); api.comment.linewise.current(); api.comment.linewise.current(); api.uncomment.linewise.current()<CR>',
  { 'a', 'b' })
case('Comment.nvim toggle.blockwise', comment, { 'a' }, ':lua require("Comment.api").toggle.blockwise.current()<CR>', { '/* a */' })

local pairs_ = once('pairs', function() require('nvim-autopairs').setup() end)
case('nvim-autopairs (', pairs_, { '' }, 'i(<Esc>', { '()' })
case("nvim-autopairs \"", pairs_, { '' }, 'i"<Esc>', { '""' })

local f = assert(io.open(os.getenv('ARTEMIS_OUT'), 'w'))
f:write(table.concat(lines, '\n') .. '\n')
f:close()
