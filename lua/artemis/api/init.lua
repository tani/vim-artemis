-- vim.api emulation for Vim. Each submodule installs functions into the table.
local A = {}

require('artemis.api.buf')(A)
require('artemis.api.win')(A)
require('artemis.api.opt')(A)
require('artemis.api.misc')(A)
require('artemis.api.cmd')(A)
require('artemis.api.extmark')(A)
require('artemis.api.more')(A)

return A
