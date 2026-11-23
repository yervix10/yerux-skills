#!/usr/bin/env bash
# The installer must change only BYPASS in ~/.claude-bridge/config and keep every other option.
set -e
P="$(cd "$(dirname "$0")/.." && pwd)/package.sh"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
sed -n '/^set_conf() {/,/^  if grep.*$/p;/^set_conf() {/,/fi; }$/p' "$P" | awk '!seen[$0]++' > "$T/fn.sh"
BR="$T"; . "$T/fn.sh"
printf 'BYPASS=0\nWIDGET=0\nALERT=600\nCOMPACT_AT=40\n' > "$T/config"
set_conf BYPASS 1
fail=0; chk() { grep -qx "$1" "$T/config" && echo "  ok   $1" || { echo "  FAIL missing $1"; fail=1; }; }
chk BYPASS=1; chk WIDGET=0; chk ALERT=600; chk COMPACT_AT=40
[ "$(grep -c '^BYPASS=' "$T/config")" = 1 ] && echo "  ok   BYPASS appears once" || { echo "  FAIL duplicated BYPASS"; fail=1; }
rm -f "$T/config"; set_conf BYPASS 1; chk BYPASS=1
exit $fail
