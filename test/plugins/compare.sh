#!/bin/sh
# Differential test: run a behaviour script on Neovim (oracle) and Vim and diff.
# usage: test/plugins/compare.sh <script-basename> <plugin-dirs>
cd "$(dirname "$0")/../.." || exit 1
script=$1; dirs=$2
nv=$(test/plugins/$script.sh nvim "$dirs")
vm=$(test/plugins/$script.sh vim "$dirs")
if [ "$nv" = "$vm" ]; then
  echo "$vm"; echo "compare: identical ($(echo "$nv" | wc -l) cases)"
else
  diff -u --label nvim --label vim /dev/fd/3 /dev/fd/4 3<<EOT 4<<EOV
$nv
EOT
$vm
EOV
  exit 1
fi
