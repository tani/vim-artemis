#!/bin/sh
# usage: test/plugins/smoke.sh <host> <plugin-dirs> <modules>
cd "$(dirname "$0")/../.." || exit 1
export ARTEMIS_ROOT=$(pwd) SMOKE_PLUGINS=$2 SMOKE_MODULES=$3
export ARTEMIS_OUT=$(mktemp)
case $1 in
  nvim) timeout 120 nvim --headless -u NONE -i NONE -c "luafile test/plugins/smoke.lua" -c "qa!" >/dev/null 2>&1 ;;
  vim)  TERM=dumb timeout 120 vim -u NONE -i NONE -N --not-a-term -c "luafile test/plugins/smoke.lua" -c "qa!" </dev/null >/dev/null 2>&1 ;;
esac
cat "$ARTEMIS_OUT"; rm -f "$ARTEMIS_OUT"
