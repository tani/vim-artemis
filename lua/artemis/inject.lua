-- Install the Neovim `vim` namespace into the running editor.
--   require('artemis.inject').setup()
-- On Neovim this only fills in missing pure-Lua pieces; on Vim it installs
-- the full emulation (stdlib, vim.api, vim.fn, vim.o/opt, vim.keymap, ...).
local M = {}

-- Vim features the emulation is built on.
local required = {
  'autocmd_add', 'autocmd_delete', 'mapset', 'maplist', 'hlset', 'hlget', 'timer_start', 'job_start',
  'win_execute', 'getbufinfo', 'readdir',
}
local optional = { 'prop_add', 'popup_create', 'listener_add', 'term_start' }

local function check_vim()
  local missing = {}
  for _, f in ipairs(required) do
    if vim.eval('exists("*' .. f .. '")') == 0 then
      missing[#missing + 1] = f .. '()'
    end
  end
  if #missing > 0 then
    error(
      'vim-artemis requires a newer Vim (9.0+ with +lua). Missing: ' .. table.concat(missing, ', '),
      0
    )
  end
  local soft = {}
  for _, f in ipairs(optional) do
    if vim.eval('exists("*' .. f .. '")') == 0 then
      soft[#soft + 1] = f .. '()'
    end
  end
  if #soft > 0 then
    -- extmarks, floating windows, buf_attach and termopen degrade without these
    M.missing_optional = soft
  end
end

function M.setup()
  if M._done then
    return
  end
  M._done = true
  if vim.fn.has('nvim') == 0 and vim.eval then
    check_vim()
  end
  require('artemis.core.luacompat').install()
  require('artemis.core.stdlib').setup()
  require('artemis.core.editor').setup()
end

return M
