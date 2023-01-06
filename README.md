# vim-artemis

vim-artemis is a Lua module for the compatibility between Vim and Neovim.
We aim at covering the Lua API for writing the Vim/ Neovim configuration
file in the single Lua file. For the list of the funcitons, see `doc/artemis.txt`.

## Example

```lua
-- You can load the artemis as follows.
local vimx = require 'artemis'

-- You can set a value to the variable
vimx.g.tex_flavor = 'latex'

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
    end
  }
end)
```
