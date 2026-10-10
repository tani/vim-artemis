#!/bin/sh
# Re-fetch the vendored Neovim runtime files.
set -e
TAG=${1:-v0.10.4}
DIR=$(dirname "$0")/../lua/artemis/vendor/nvim
for f in shared iter inspect F version uri _options keymap ui fs highlight _system; do
  curl -fsS -o "$DIR/$f.lua" "https://raw.githubusercontent.com/neovim/neovim/$TAG/runtime/lua/vim/$f.lua"
done
curl -fsS -o "$DIR/LICENSE" "https://raw.githubusercontent.com/neovim/neovim/$TAG/LICENSE.txt"
