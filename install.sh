#!/usr/bin/env bash
# yerux-skills installer (Linux, macOS, WSL): finds every Claude Code / Codex account and installs the featured package
# (agent-bridge) plus any of the other skills. Package-specific logic lives in agent-bridge/package.sh.
# Windows: use install.ps1.
# Interactive menu when run from a terminal; --yes accepts everything detected.
# Usage: ./install.sh [--yes] [--skills a,b|all|none] [--dry-run] [--no-bypass] [--no-path] [--name DIR=NAME]... [--claude-dir DIR]... [--codex-dir DIR]...
#        ./install.sh --list | --uninstall [--dry-run]
set -eo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"; SRC="$ROOT/agent-bridge"; BR="$HOME/.claude-bridge"; MANIFEST="$HOME/.yerux-skills/installed.txt"
DRY=0; MODE=install; OVERS=""; CLAUDE_LIST=""; CODEX_LIST=""
YES=0; PKG_AB=1; SEL_SKILLS=""; REPO_ROOT="$ROOT"; OPT_HOOKS=1; OPT_SKILL=1; OPT_BYPASS=1; OPT_PATH=1; TTY="${AGENT_BRIDGE_TTY:-/dev/tty}"
[ -f "$ROOT/lib/ui.sh" ] && . "$ROOT/lib/ui.sh" || { ui_banner() { :; }; ui_h() { echo "$1"; }; ui_run() { local l="$1"; shift; "$@" && echo "  ok $l"; }; ui_box() { shift; printf '%s\n' "$@"; }; ui_info() { echo "$1"; }; ui_warn() { echo "$1"; }; ui_account_row() { echo "  $1) [$2] $3 $4 $5"; }; S_ARROW=">"; CYN=""; RST=""; DIM=""; BOLD=""; GRN=""; GRY=""; }
say() { echo "$@"; }
tilde() { case "$1" in "$HOME"*) printf '~%s' "${1#$HOME}";; *) printf '%s' "$1";; esac; }
die() { echo "error: $*" >&2; exit 1; }

. "$SRC/package.sh"

# ---------- arguments ----------
while [ $# -gt 0 ]; do case "$1" in
  --skills) [ -n "${2:-}" ] || die "--skills needs a list (a,b | all | none)"; SKILLS_ARG="$2"; shift;;
  --dry-run) DRY=1;; --yes|-y) YES=1;; --no-bypass) OPT_BYPASS=0;; --no-path) OPT_PATH=0;; --uninstall) MODE=uninstall;; --list) MODE=list;;
  --name) [ -n "${2:-}" ] || die "--name needs DIR=NAME"; OVERS="$OVERS
${2%%=*}=${2#*=}"; shift;;
  --claude-dir) [ -n "${2:-}" ] || die "--claude-dir needs a path"; CLAUDE_LIST="$CLAUDE_LIST
$2"; shift;;
  --codex-dir) [ -n "${2:-}" ] || die "--codex-dir needs a path"; CODEX_LIST="$CODEX_LIST
$2"; shift;;
  -h|--help) sed -n '2,9p' "$0"; exit 0;;
  *) die "unknown option: $1";; esac; shift; done

# ---------- operating system ----------
case "$(uname -s)" in
  Linux) OS=linux; grep -qi microsoft /proc/version 2>/dev/null && OS=wsl;;
  Darwin) OS=macos;;
  MINGW*|MSYS*|CYGWIN*) die "Windows detected. Run install.ps1 from PowerShell instead.";;
  *) OS=unknown;;
esac

# ---------- dependencies ----------
pm_hint() {
  if command -v apt-get >/dev/null; then echo "sudo apt install $*"
  elif command -v dnf >/dev/null; then echo "sudo dnf install $*"
  elif command -v pacman >/dev/null; then echo "sudo pacman -S $*"
  elif command -v apk >/dev/null; then echo "sudo apk add $*"
  elif command -v zypper >/dev/null; then echo "sudo zypper install $*"
  elif command -v brew >/dev/null; then echo "brew install $*"
  else echo "install: $*"; fi; }
missing=""; for c in jq awk sed cksum mktemp; do command -v "$c" >/dev/null 2>&1 || missing="$missing $c"; done
command -v python3 >/dev/null 2>&1 || command -v uuidgen >/dev/null 2>&1 || missing="$missing python3"
[ -z "$missing" ] || die "missing tools:$missing  ->  $(pm_hint $missing)"
[ "$OS" = macos ] && ! command -v timeout >/dev/null && ! command -v gtimeout >/dev/null && say "note: no 'timeout' found; runner tasks will have no time limit (brew install coreutils adds one)."

# ---------- discovery ----------
norm() { local p="$1"; p="${p//\"/}"; p="${p//\'/}"; case "$p" in "~"*) p="$HOME${p#\~}";; esac
  p="${p//\$\{HOME\}/$HOME}"; p="${p//\$HOME/$HOME}"; case "$p" in *'$'*) return 1;; esac; echo "${p%/}"; }
has_line() { printf '%s\n' "$1" | grep -Fxq -- "$2"; }
add_dir() { # kind dir
  local d; d="$(norm "$2")" || return 0; [ -n "$d" ] && [ -d "$d" ] || return 0
  [ "$(basename "$d")" = ".claude-bridge" ] && return 0
  if [ "$1" = claude ]; then has_line "$CLAUDE_LIST" "$d" || CLAUDE_LIST="$CLAUDE_LIST
$d"; else has_line "$CODEX_LIST" "$d" || CODEX_LIST="$CODEX_LIST
$d"; fi; }
# normalize user-given dirs
tmp="$CLAUDE_LIST"; CLAUDE_LIST=""; while IFS= read -r d; do [ -n "$d" ] && add_dir claude "$d"; done <<EOF2
$tmp
EOF2
tmp="$CODEX_LIST"; CODEX_LIST=""; while IFS= read -r d; do [ -n "$d" ] && add_dir codex "$d"; done <<EOF2
$tmp
EOF2
# default folders and ~/.claude-* / ~/.codex-* by name pattern
for d in "$HOME/.claude" "$HOME"/.claude-*; do
  [ -d "$d" ] || continue
  for m in settings.json .credentials.json projects commands skills; do [ -e "$d/$m" ] && { add_dir claude "$d"; break; }; done; done
for d in "$HOME/.codex" "$HOME"/.codex-*; do
  [ -d "$d" ] || continue
  for m in auth.json config.toml hooks.json sessions; do [ -e "$d/$m" ] && { add_dir codex "$d"; break; }; done; done
# current environment
[ -n "${CLAUDE_CONFIG_DIR:-}" ] && add_dir claude "$CLAUDE_CONFIG_DIR"
[ -n "${CODEX_HOME:-}" ] && add_dir codex "$CODEX_HOME"
# aliases / exports in shell startup files
for rc in "$HOME/.bashrc" "$HOME/.bash_aliases" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.zshenv" "$HOME/.config/fish/config.fish"; do
  [ -f "$rc" ] || continue
  for v in CLAUDE_CONFIG_DIR CODEX_HOME; do
    kind=claude; [ "$v" = CODEX_HOME ] && kind=codex
    while IFS= read -r val; do [ -n "$val" ] && add_dir "$kind" "$val"; done <<EOF2
$(grep -v '^[[:space:]]*#' "$rc" | grep -Eo "$v[= ][^[:space:];&|)]+" | sed -E "s/^$v[= ]//")
EOF2
  done; done
CLAUDE_LIST="$(printf '%s\n' "$CLAUDE_LIST" | sed '/^$/d' | sort -u)"; CODEX_LIST="$(printf '%s\n' "$CODEX_LIST" | sed '/^$/d' | sort -u)"

# ---------- names (names.conf lines: DIR=NAME; existing names are kept) ----------
conf="$BR/names.conf"; MAP=""; [ -f "$conf" ] && MAP="$(cat "$conf")"
get_name() { printf '%s\n' "$MAP" | awk -F= -v k="$1" '$1==k{print $2; exit}'; }
set_name() { MAP="$(printf '%s\n' "$MAP" | awk -F= -v k="$1" '$1!=k && NF')
$1=$2"; }
next_name() { printf '%s\n' "$MAP" | awk -F= -v p="$1" 'BEGIN{m=0} $2 ~ "^"p"-[0-9]+$" {n=$2; sub(/.*-/,"",n); if (n+0>m) m=n+0} END{print p "-" m+1}'; }
existing_name() { local d="$1" v=""
  [ -f "$d/settings.json" ] && v="$(jq -r '.env.BRIDGE_NAME // empty' "$d/settings.json" 2>/dev/null || true)"
  [ -z "$v" ] && [ -f "$d/hooks.json" ] && v="$(grep -o 'BRIDGE_NAME=[A-Za-z0-9_-]*' "$d/hooks.json" 2>/dev/null | head -1 | cut -d= -f2 || true)"
  echo "$v"; }
assign() { # dir prefix
  local d="$1" n; n="$(printf '%s\n' "$OVERS" | awk -F= -v k="$d" '$1==k{print $2; exit}')"
  [ -z "$n" ] && n="$(get_name "$d")"; [ -z "$n" ] && n="$(existing_name "$d")"; [ -z "$n" ] && n="$(next_name "$2")"
  case "$n" in *[!A-Za-z0-9_-]*|"") die "invalid name for $d: '$n'";; esac
  set_name "$d" "$n"; }
while IFS= read -r d; do [ -n "$d" ] && assign "$d" agent; done <<EOF2
$CLAUDE_LIST
EOF2
while IFS= read -r d; do [ -n "$d" ] && assign "$d" codex; done <<EOF2
$CODEX_LIST
EOF2

if [ "$MODE" = list ]; then
  say "system: $OS"
  while IFS= read -r d; do [ -n "$d" ] && say "claude  $(get_name "$d")  $d"; done <<EOF2
$CLAUDE_LIST
EOF2
  while IFS= read -r d; do [ -n "$d" ] && say "codex   $(get_name "$d")  $d"; done <<EOF2
$CODEX_LIST
EOF2
  exit 0; fi


# ---------- skills of this repo (every folder with a SKILL.md besides agent-bridge) ----------
SK_NAMES=(); SK_DESC=()
for d in "$REPO_ROOT"/*/; do n="$(basename "$d")"; [ "$n" = agent-bridge ] && continue; [ -f "$d/SKILL.md" ] || continue
  desc="$(awk '/^description:/{ s=$0; sub(/^description:[ ]*/,"",s); if (s ~ /^[>|]/ || s=="") { getline s; sub(/^[ ]+/,"",s) } print s; exit }' "$d/SKILL.md" | cut -c1-64)"
  SK_NAMES+=("$n"); SK_DESC+=("$desc"); done
case "${SKILLS_ARG:-}" in all) SEL_SKILLS="${SK_NAMES[*]:-}";; none|"") ;; *) SEL_SKILLS="${SKILLS_ARG//,/ }";; esac

# ---------- interactive menu (arrows + space) ----------
can_ask() { [ "${TERM:-}" = dumb ] && return 1; [ -n "${AGENT_BRIDGE_TTY:-}" ] && [ -r "$TTY" ] && return 0; ( : < /dev/tty ) 2>/dev/null; }
ask() { printf '  %s%s%s %s' "$CYN" "$S_ARROW" "$RST" "$1" >&2; IFS= read -r REPLY <&3 || REPLY=""; }
yn() { local def="$2" d="Y/n"; [ "$2" = 0 ] && d="y/N"; ask "$1 ${DIM}[$d]${RST} "; case "$REPLY" in [Yy]*) return 0;; [Nn]*) return 1;; *) [ "$def" = 1 ];; esac; }
MS_L=(); MS_S=(); MS_ON=(); MS_F=(); MS_N=0; MS_CUR=0; MS_EXTRA=0; MS_CB=""
MS_TOP=0; MS_DRAWN=0
ms_geom() { MS_ROWS="$(tput lines 2>/dev/null || echo 24)"; MS_COLS="$(tput cols 2>/dev/null || echo 80)"
  case "$MS_ROWS" in ''|*[!0-9]*) MS_ROWS=24;; esac; case "$MS_COLS" in ''|*[!0-9]*) MS_COLS=80;; esac
  MS_VIS=$((MS_ROWS - 9)); [ $MS_VIS -lt 5 ] && MS_VIS=5; [ $MS_VIS -gt $MS_N ] && MS_VIS=$MS_N; return 0; }
ms_clamp() { [ $MS_CUR -lt $MS_TOP ] && MS_TOP=$MS_CUR; [ $MS_CUR -ge $((MS_TOP + MS_VIS)) ] && MS_TOP=$((MS_CUR - MS_VIS + 1)); [ $MS_TOP -lt 0 ] && MS_TOP=0; return 0; }
ms_draw() { local i p m lab sub max end
  ms_geom; ms_clamp; end=$((MS_TOP + MS_VIS)); [ $end -gt $MS_N ] && end=$MS_N; MS_DRAWN=0
  i=$MS_TOP; while [ $i -lt $end ]; do
    if [ "${MS_ON[$i]}" = 1 ]; then m="${GRN}${S_ON}${RST}"; else m="${GRY}${S_OFF}${RST}"; fi
    if [ $i -eq $MS_CUR ]; then p="${CYN}${S_ARROW}${RST}"; lab="${BOLD}${MS_L[$i]}${RST}"; else p=" "; lab="${MS_L[$i]}"; fi
    max=$((MS_COLS - ${#MS_L[$i]} - 14)); sub="${MS_S[$i]}"
    if [ "${MS_F[$i]:-0}" = 1 ]; then lab="${BOLD}${MAG}★ ${MS_L[$i]}${RST}  ${MAG}featured${RST}"; max=$((max - 10)); fi
    if [ $max -lt 8 ]; then sub=""; else sub="${sub:0:$max}"; fi
    printf '\033[2K\r  %s %s  %s  %s%s%s\n' "$p" "$m" "$lab" "$DIM" "$sub" "$RST"; MS_DRAWN=$((MS_DRAWN+1)); i=$((i+1)); done
  if [ $MS_N -gt $MS_VIS ]; then printf '\033[2K\r  %s%d/%d%s\n' "$DIM" $((MS_CUR+1)) $MS_N "$RST"; MS_DRAWN=$((MS_DRAWN+1)); fi; }
ms_run() { local k rest first=1 i
  MS_CUR=0; MS_TOP=0; MS_EXTRA=0; MS_DRAWN=0; ui_cursor_off
  while :; do
    if [ $first = 0 ] && [ $((MS_DRAWN + MS_EXTRA)) -gt 0 ]; then printf '\033[%dA\033[J' $((MS_DRAWN + MS_EXTRA)); fi
    first=0; MS_EXTRA=0; ms_draw
    IFS= read -rsn1 -u 3 k || k=""
    case "$k" in
      "") break;;
      " ") [ $MS_N -gt 0 ] && { [ "${MS_ON[$MS_CUR]}" = 1 ] && MS_ON[$MS_CUR]=0 || MS_ON[$MS_CUR]=1; };;
      $'\033') IFS= read -rsn2 -t 1 -u 3 rest || rest=""
        case "$rest" in "[A") [ $MS_CUR -gt 0 ] && MS_CUR=$((MS_CUR-1));; "[B") [ $MS_CUR -lt $((MS_N-1)) ] && MS_CUR=$((MS_CUR+1));; esac;;
      k|K) [ $MS_CUR -gt 0 ] && MS_CUR=$((MS_CUR-1));;
      j|J) [ $MS_CUR -lt $((MS_N-1)) ] && MS_CUR=$((MS_CUR+1));;
      a) i=0; while [ $i -lt $MS_N ]; do MS_ON[$i]=1; i=$((i+1)); done;;
      n) i=0; while [ $i -lt $MS_N ]; do MS_ON[$i]=0; i=$((i+1)); done;;
      *) [ -n "$MS_CB" ] && "$MS_CB" "$k";;
    esac
  done
  ui_cursor_on; return 0; }
hint() { printf '  %s%s%s\n' "$DIM" "$1" "$RST"; }
acc_refresh() { local i=0; while [ $i -lt $MS_N ]; do MS_L[$i]="$(get_name "${ACC_DIR[$i]}")"; MS_S[$i]="${ACC_KIND[$i]}   $(tilde "${ACC_DIR[$i]}")"; i=$((i+1)); done; }
acc_cb() { case "$1" in
  r) ui_cursor_on; printf '\n  %s%s%s new name for %s: ' "$CYN" "$S_ARROW" "$RST" "${MS_L[$MS_CUR]}"; IFS= read -r REPLY <&3 || REPLY=""; ui_cursor_off; MS_EXTRA=2
     case "$REPLY" in ""|*[!A-Za-z0-9_-]*) ;; *) if printf '%s\n' "$MAP" | awk -F= -v k="${ACC_DIR[$MS_CUR]}" -v v="$REPLY" '$1!=k && $2==v{f=1} END{exit !f}'; then :; else set_name "${ACC_DIR[$MS_CUR]}" "$REPLY"; acc_refresh; fi;; esac;;
  +) ui_cursor_on; printf '\n  %s%s%s type (claude/codex): ' "$CYN" "$S_ARROW" "$RST"; IFS= read -r kind <&3 || kind=""
     printf '  %s%s%s folder: ' "$CYN" "$S_ARROW" "$RST"; IFS= read -r REPLY <&3 || REPLY=""; ui_cursor_off; MS_EXTRA=3
     local p; p="$(norm "$REPLY")" || p=""
     if { [ "$kind" = claude ] || [ "$kind" = codex ]; } && [ -n "$p" ] && [ -d "$p" ]; then
       assign "$p" "$([ "$kind" = claude ] && echo agent || echo codex)"
       ACC_KIND[$MS_N]="$kind"; ACC_DIR[$MS_N]="$p"; MS_ON[$MS_N]=1; MS_F[$MS_N]=0; MS_N=$((MS_N+1)); acc_refresh; fi;;
  esac; }
run_menu() {
  exec 3< "$TTY"
  local i d
  # --- accounts ---
  ACC_KIND=(); ACC_DIR=(); MS_L=(); MS_S=(); MS_ON=(); MS_F=(); MS_N=0
  while IFS= read -r d; do [ -n "$d" ] && { ACC_KIND[$MS_N]=claude; ACC_DIR[$MS_N]="$d"; MS_ON[$MS_N]=1; MS_N=$((MS_N+1)); }; done <<EOF2
$CLAUDE_LIST
EOF2
  while IFS= read -r d; do [ -n "$d" ] && { ACC_KIND[$MS_N]=codex; ACC_DIR[$MS_N]="$d"; MS_ON[$MS_N]=1; MS_N=$((MS_N+1)); }; done <<EOF2
$CODEX_LIST
EOF2
  acc_refresh
  ui_h "Accounts"; hint "↑↓ move · space select · r rename · + add folder · enter continue"; echo
  MS_CB=acc_cb; ms_run; MS_CB=""
  CLAUDE_LIST=""; CODEX_LIST=""; i=0
  while [ $i -lt $MS_N ]; do
    if [ "${MS_ON[$i]}" = 1 ]; then
      if [ "${ACC_KIND[$i]}" = claude ]; then CLAUDE_LIST="$CLAUDE_LIST
${ACC_DIR[$i]}"; else CODEX_LIST="$CODEX_LIST
${ACC_DIR[$i]}"; fi; fi; i=$((i+1)); done
  # --- packages ---
  MS_L=("agent-bridge"); MS_S=("Claude Code + Codex sessions that talk to each other"); MS_ON=(1); MS_F=(1); MS_N=1
  i=0; while [ $i -lt ${#SK_NAMES[@]} ]; do MS_L[$MS_N]="${SK_NAMES[$i]}"; MS_S[$MS_N]="${SK_DESC[$i]}"; MS_ON[$MS_N]=0; MS_F[$MS_N]=0; MS_N=$((MS_N+1)); i=$((i+1)); done
  ui_h "Packages"; hint "↑↓ move · space select · a all · n none · enter continue"; echo
  ms_run
  PKG_AB="${MS_ON[0]}"; SEL_SKILLS=""; i=1
  while [ $i -lt $MS_N ]; do [ "${MS_ON[$i]}" = 1 ] && SEL_SKILLS="$SEL_SKILLS ${MS_L[$i]}"; i=$((i+1)); done
  SEL_SKILLS="${SEL_SKILLS# }"
  # --- agent-bridge options ---
  if [ "$PKG_AB" = 1 ]; then ab_options_menu; fi
  NACC=$(printf '%s\n%s\n' "$CLAUDE_LIST" "$CODEX_LIST" | sed '/^$/d' | wc -l | tr -d ' ')
  echo; ui_info "Accounts: $NACC   ·   agent-bridge: $([ "$PKG_AB" = 1 ] && echo yes || echo no)   ·   extra skills: $(printf '%s' "$SEL_SKILLS" | wc -w | tr -d ' ')"
  yn "Proceed?" 1 || { echo "cancelled" >&2; exit 0; }
  exec 3<&-
}
[ "$MODE" = install ] && ui_banner
if [ "$MODE" = install ] && [ $YES = 0 ] && [ $DRY = 0 ] && can_ask; then run_menu; fi

# ---------- generic helpers ----------
act() { if [ $DRY = 1 ]; then say "  [dry-run] $*"; else eval "$@"; fi; }
each() { local list="$1"; shift; while IFS= read -r d; do [ -n "$d" ] && "$@" "$d"; done <<EOF2
$list
EOF2
}

# extra skills installed by this installer are recorded so --uninstall can remove exactly those
manifest_add() { mkdir -p "$(dirname "$MANIFEST")"; printf '%s\t%s\n' "$1" "$2" >> "$MANIFEST"; }
install_skills() { local d="$1" n; for n in $SEL_SKILLS; do [ -f "$REPO_ROOT/$n/SKILL.md" ] || continue
  if [ $DRY = 1 ]; then say "  [dry-run] skill $n -> $d/skills/$n"; continue; fi
  mkdir -p "$d/skills"; rm -rf "$d/skills/$n"; cp -R "$REPO_ROOT/$n" "$d/skills/$n"; rm -rf "$d/skills/$n/.git"
  grep -Fxq "$d	$n" "$MANIFEST" 2>/dev/null || manifest_add "$d" "$n"; done; return 0; }
remove_skills() { local d="$1" n; [ -f "$MANIFEST" ] || return 0
  while IFS="	" read -r dir n; do [ "$dir" = "$d" ] && [ -n "$n" ] && { [ $DRY = 1 ] || rm -rf "$d/skills/$n"; say "  removed skill $n"; }; done < "$MANIFEST"
  if [ $DRY = 0 ]; then awk -F'	' -v d="$d" '$1 != d' "$MANIFEST" > "$MANIFEST.tmp"; mv "$MANIFEST.tmp" "$MANIFEST"; fi; return 0; }

# ---------- uninstall ----------
un_claude() { say "uninstalling Claude: $1"; ab_un_claude "$1"; remove_skills "$1"; }
un_codex() { say "uninstalling Codex: $1"; ab_un_codex "$1"; remove_skills "$1"; }
if [ "$MODE" = uninstall ]; then each "$CLAUDE_LIST" un_claude; each "$CODEX_LIST" un_codex
  say "done. agent-bridge and the extra skills this installer added were removed. The mailbox $BR (messages, names.conf) is kept."; exit 0; fi

# ---------- install ----------
in_claude() { [ "$PKG_AB" = 1 ] && ab_install_claude "$1"; install_skills "$1"; return 0; }
in_codex() { [ "$PKG_AB" = 1 ] && ab_install_codex "$1"; install_skills "$1"; return 0; }
step_claude() { ui_run "Claude  $(get_name "$1")  ${DIM}$(tilde "$1")${RST}" in_claude "$1"; }
step_codex() { ui_run "Codex   $(get_name "$1")  ${DIM}$(tilde "$1")${RST}" in_codex "$1"; }

ui_h "Installing"
if [ "$PKG_AB" != 1 ]; then :; elif [ $DRY = 1 ]; then say "  [dry-run] scripts -> $BR/bin"; else ui_run "Scripts  ${DIM}$(tilde "$BR/bin")${RST}" do_scripts; fi
if [ "$PKG_AB" = 1 ] && [ $OPT_PATH = 1 ] && [ $DRY = 0 ]; then ui_run "Commands on PATH  ${DIM}~/.local/bin${RST}" do_path; fi
each "$CLAUDE_LIST" step_claude; each "$CODEX_LIST" step_codex
NACC=$(printf '%s\n%s\n' "$CLAUDE_LIST" "$CODEX_LIST" | sed '/^$/d' | wc -l | tr -d ' ')
[ "$NACC" -gt 0 ] || ui_warn "No accounts found. Use --claude-dir DIR / --codex-dir DIR."
if [ $DRY = 1 ]; then say; say "dry-run finished: nothing was written."; exit 0; fi
lines=("${GRN}${S_OK}${RST} $NACC account(s) configured")
[ "${UI_FAILS:-0}" -gt 0 ] && lines=("${RED}${S_FAIL}${RST} ${UI_FAILS} step(s) failed - see $UI_LOG")
[ -n "$SEL_SKILLS" ] && lines+=("${GRN}${S_OK}${RST} skills: $SEL_SKILLS")
lines+=("" "${BOLD}Next steps${RST}" "  1. Restart open Claude/Codex sessions")
[ "$PKG_AB" = 1 ] && ab_next_steps
ui_box "Done" "${lines[@]}"
exit 0
