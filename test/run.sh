#!/bin/sh
# Run the specs on both hosts. Usage: test/run.sh [vim|nvim ...]
# Success is decided from the report (Vim's -es exit status is unreliable).
cd "$(dirname "$0")/.." || exit 1
export ARTEMIS_ROOT=$(pwd)
export ARTEMIS_SPECS=$(ls test/spec/*_spec.lua | sed "s|^|$ARTEMIS_ROOT/|" | tr '\n' ',')
rc=0
hosts=${*:-"nvim vim"}
for h in $hosts; do
  export ARTEMIS_OUT=$(mktemp)
  case $h in
    nvim) timeout 120 nvim --headless -u NONE -i NONE -c "luafile test/run.lua" -c "qa!" >/dev/null 2>&1 ;;
    vim)  TERM=dumb timeout 120 vim -u NONE -i NONE -N --not-a-term -c "luafile test/run.lua" -c "qa!" </dev/null >/dev/null 2>&1 ;;
  esac
  cat "$ARTEMIS_OUT"
  tail -n 1 "$ARTEMIS_OUT" | grep -q ' 0 failed$' || rc=1
  rm -f "$ARTEMIS_OUT"
done
exit $rc
