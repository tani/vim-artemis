-- Install the Neovim `vim` namespace into the running editor.
--   require('artemis.inject').setup()
-- On Neovim this only fills in missing pure-Lua pieces; on Vim it installs
-- the full emulation (stdlib, vim.api, vim.fn, vim.o/opt, vim.keymap, ...).
local M = {}

function M.setup()
  if M._done then
    return
  end
  M._done = true
  require('artemis.core.luacompat').install()
  require('artemis.core.stdlib').setup()
  require('artemis.core.editor').setup()
end

return M
