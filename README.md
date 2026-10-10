# vim-artemis

vim-artemis is a Lua compatibility layer between Vim and Neovim.

- **Run Neovim Lua plugins on Vim.** `require('artemis.inject').setup()` fills
  Vim's `vim` table with the Neovim API: `vim.api`, `vim.fn`, `vim.g/b/w/t/v`,
  `vim.o/bo/wo/opt`, `vim.keymap`, `vim.cmd`, `vim.uv`, `vim.system`,
  `vim.schedule`, `vim.iter`, `vim.fs`, `vim.v:lua`-style calls, extmarks,
  floating windows (as popups) and more. Neovim plugins such as mini.nvim,
  Comment.nvim, nvim-surround and plenary.nvim load and run unmodified.
- **Write one config for both editors** with the original `artemis.*` API
  (see below). `require('artemis')` also performs the injection.
- On Neovim, injection only back-fills functions missing from older versions
  (e.g. `vim.iter`, `vim.islist`, `vim.keycode` on 0.9).

Requirements: Vim 9.0+ built with `+lua` (Lua 5.1+), or Neovim 0.9+.

```vim
" vimrc: put the plugin on the runtimepath, then in Lua:
lua require('artemis.inject').setup()
lua require('mini.surround').setup()   " a Neovim plugin, on Vim
```

Details: [`docs/design.md`](docs/design.md) (architecture),
[`docs/compat-table.md`](docs/compat-table.md) (`vim.api` coverage),
[`docs/limitations.md`](docs/limitations.md) (what differs / cannot work).
Third-party code vendored from Neovim is listed in
[`lua/artemis/vendor/NOTICE.md`](lua/artemis/vendor/NOTICE.md).

Run the tests on both hosts with `test/run.sh`.

## Example

```lua
-- You can load the artemis as follows.
local vimx = require 'artemis'

-- You can set a value to the variable
vimx.g.tex_flavor = 'latex'

-- You can set a value to the part of the dictionary
vimx.g.lightline.colorscheme = 'gruvbox_material'

-- You can call Vim command naturally
vimx.cmd.packadd 'vim-jetpack'

require('jetpack.packer').startup(function(use)
  use {
    'cohama/lexima.vim',
    config = function()
      -- fn proxies arguments using artemis.cast
      vimx.fn['lexima#add_rule'] {
        at = ';->\\%#',
        input = '\\rightarrow'
      }
      -- You can also chain with the dot instead of the sharp
      vimx.fn.lexima.add_rule {
        at = ';->\\%#',
        input = '\\rightarrow'
      }
    end
  }
end)
```
