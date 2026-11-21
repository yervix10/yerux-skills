# agent-bridge UI helpers: colors, banner, spinner, boxes. Falls back to plain text when output is not a
# terminal, NO_COLOR is set, or TERM=dumb. Compatible with bash 3.2.
UI_COLOR=0; [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != dumb ] && UI_COLOR=1
UI_UTF=0; case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *UTF-8*|*utf8*|*UTF8*) UI_UTF=1;; esac
UI_LOG="${TMPDIR:-/tmp}/agent-bridge-install.$$.log"; : > "$UI_LOG" 2>/dev/null || UI_LOG=/dev/null
if [ $UI_COLOR = 1 ]; then
  ESC="$(printf '\033')"; RST="${ESC}[0m"; BOLD="${ESC}[1m"; DIM="${ESC}[2m"
  c() { printf '%s[38;5;%sm' "$ESC" "$1"; }
  GRN="$(c 78)"; RED="$(c 203)"; CYN="$(c 81)"; YEL="$(c 221)"; MAG="$(c 177)"; GRY="$(c 245)"; BLU="$(c 39)"
else c() { :; }; RST=""; BOLD=""; DIM=""; GRN=""; RED=""; CYN=""; YEL=""; MAG=""; GRY=""; BLU=""; fi
if [ $UI_UTF = 1 ]; then
  S_OK="✔"; S_FAIL="✖"; S_ARROW="❯"; S_ON="◉"; S_OFF="○"; S_DOT="•"; S_WARN="!"; S_DRY="◌"
  B_TL="╭"; B_TR="╮"; B_BL="╰"; B_BR="╯"; B_H="─"; B_V="│"
  UI_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
else
  S_OK="+"; S_FAIL="x"; S_ARROW=">"; S_ON="(*)"; S_OFF="( )"; S_DOT="*"; S_WARN="!"; S_DRY="◌"
  B_TL="+"; B_TR="+"; B_BL="+"; B_BR="+"; B_H="-"; B_V="|"
  UI_FRAMES=("-" "\\" "|" "/")
fi
ui_cursor_off() { [ $UI_COLOR = 1 ] && printf '%s[?25l' "$ESC"; return 0; }
ui_cursor_on()  { [ $UI_COLOR = 1 ] && printf '%s[?25h' "$ESC"; return 0; }
trap 'ui_cursor_on' EXIT
ui_sleep() { [ $UI_COLOR = 1 ] && [ -z "${UI_FAST:-}" ] && sleep "$1"; return 0; }
ui_clear() { [ $UI_COLOR = 1 ] && printf '%s[2J%s[H' "$ESC" "$ESC"; return 0; }
ui_rep() { local s="" i=0; while [ $i -lt "$2" ]; do s="$s$1"; i=$((i+1)); done; printf '%s' "$s"; }

ui_bline() { # border-color, visible-length, styled-text
  printf '  %s%s%s%s%*s%s%s%s\n' "$1" "$B_V" "$RST" "$3" $((UI_W - $2)) "" "$1" "$B_V" "$RST"; }
ui_banner() {
  local ver="${AGENT_BRIDGE_VERSION:-1.2.0}" t1="yerux - skills" t2="installer" t3="* featured: agent-bridge"
  UI_W=50
  echo
  printf '  %s%s%s%s\n' "$(c 45)" "$B_TL" "$(ui_rep "$B_H" $UI_W)" "$B_TR$RST"; ui_sleep 0.05
  ui_bline "$(c 45)" $((2+${#t1}+2+${#t2}+3+1+${#ver})) "  ${BOLD}${CYN}${t1}${RST}  ${GRY}${t2}${RST}   ${DIM}v${ver}${RST}"; ui_sleep 0.05
  ui_bline "$(c 39)" $((2+${#t3})) "  ${BOLD}${MAG}${t3}${RST}"; ui_sleep 0.05
  printf '  %s%s%s%s\n' "$(c 33)" "$B_BL" "$(ui_rep "$B_H" $UI_W)" "$B_BR$RST"
  echo
}
ui_h() { printf '\n  %s%s%s%s\n' "$BOLD" "$MAG" "$1" "$RST"; }
ui_info() { printf '  %s%s%s %s\n' "$CYN" "$S_DOT" "$RST" "$1"; }
ui_warn() { printf '  %s%s%s %s\n' "$YEL" "$S_WARN" "$RST" "$1"; }
ui_okline() { printf '  %s%s%s %s\n' "$GRN" "$S_OK" "$RST" "$1"; }
ui_failline() { printf '  %s%s%s %s\n' "$RED" "$S_FAIL" "$RST" "$1"; }
ui_account_row() { # n on kind name dir
  local mark="$S_OFF" col="$GRY"; [ "$2" = 1 ] && { mark="$S_ON"; col="$GRN"; }
  printf '   %s%2s%s  %s%s%s  %s%-6s%s %s%-10s%s %s%s%s\n' "$BOLD" "$1" "$RST" "$col" "$mark" "$RST" "$BLU" "$3" "$RST" "$BOLD" "$4" "$RST" "$DIM" "$5" "$RST"; }

# ui_run <label> <cmd...>: runs the command with an animated spinner, then shows ok/fail.
UI_FAILS=0
ui_run() {
  local label="$1"; shift
  if [ "${DRY:-0}" = 1 ]; then
    printf '  %s%s%s %s\n' "$YEL" "$S_DRY" "$RST" "$label"
    "$@" | sed "s/^ *\[dry-run\] */      ${DIM}/; s/\$/${RST}/"; return 0; fi
  if [ $UI_COLOR = 0 ]; then
    if "$@" >> "$UI_LOG" 2>&1; then echo "  [ok] $label"; else echo "  [fail] $label"; UI_FAILS=$((UI_FAILS+1)); tail -3 "$UI_LOG"; fi; return 0; fi
  "$@" >> "$UI_LOG" 2>&1 &
  local pid=$! i=0 n=${#UI_FRAMES[@]} rc=0
  ui_cursor_off
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r  %s%s%s %s' "$CYN" "${UI_FRAMES[$((i % n))]}" "$RST" "$label"; i=$((i+1)); sleep 0.08; done
  wait "$pid" && rc=0 || rc=$?
  printf '\r%s[K' "$ESC"; ui_cursor_on
  if [ $rc = 0 ]; then ui_okline "$label"; else ui_failline "$label"; UI_FAILS=$((UI_FAILS+1)); printf '%s' "$DIM"; tail -3 "$UI_LOG" | sed 's/^/      /'; printf '%s' "$RST"; fi
  return 0; }

ui_box() { # title, then lines as args
  local title="$1"; shift; local w=54 line
  printf '\n  %s%s%s %s%s%s %s%s\n' "$GRN" "$B_TL" "$B_H" "$BOLD" "$title" "$RST$GRN" "$(ui_rep "$B_H" $((w-${#title}-3)))" "$B_TR$RST"
  for line in "$@"; do printf '  %s%s%s  %s\n' "$GRN" "$B_V" "$RST" "$line"; done
  printf '  %s%s%s%s\n\n' "$GRN" "$B_BL" "$(ui_rep "$B_H" $((w)))" "$B_BR$RST"; }
