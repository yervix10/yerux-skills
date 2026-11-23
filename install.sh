#!/usr/bin/env bash
# yerux-skills installer (Linux, macOS, WSL): finds Claude Code / Codex / Kiro CLI / Google Antigravity (agy) / Cursor CLI / GitHub Copilot CLI / OpenCode accounts and installs the featured package
# (agent-bridge) plus any of the other skills. Package-specific logic lives in skills/agent-bridge/package.sh.
# Windows: use install.ps1.
# Interactive menu when run from a terminal; --yes accepts everything detected.
# Usage: ./install.sh [--yes] [--skills a,b|all|none] [--dry-run] [--no-bypass] [--safe] [--no-path] [--no-trust] [--no-statusline] [--check [--fix]] [--name DIR=NAME]... [--claude-dir DIR]... [--codex-dir DIR]... [--kiro-dir DIR]... [--agy-dir DIR]... [--cursor-dir DIR]... [--copilot-dir DIR]... [--opencode-dir DIR]... [--opencode-workers N]
#        ./install.sh --list | --uninstall [--dry-run]
set -eo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"; SRC="$ROOT/skills/agent-bridge"; BR="$HOME/.claude-bridge"; MANIFEST="$HOME/.yerux-skills/installed.txt"
DRY=0; FIX=0; MODE=install; OVERS=""; CLAUDE_LIST=""; CODEX_LIST=""; KIRO_LIST=""; AGY_LIST=""; CURSOR_LIST=""; COPILOT_LIST=""; OPENCODE_LIST=""; OC_WORKERS=0
YES=0; PKG_AB=1; SEL_SKILLS=""; REPO_ROOT="$ROOT/skills"; OPT_HOOKS=1; OPT_SKILL=1; OPT_BYPASS=1; OPT_PATH=1; OPT_TRUST=1; OPT_STATUSLINE=1; TTY="${AGENT_BRIDGE_TTY:-/dev/tty}"
[ -f "$ROOT/lib/ui.sh" ] && . "$ROOT/lib/ui.sh" || { ui_banner() { :; }; ui_h() { echo "$1"; }; ui_run() { local l="$1"; shift; "$@" && echo "  ok $l"; }; ui_box() { shift; printf '%s\n' "$@"; }; ui_info() { echo "$1"; }; ui_warn() { echo "$1"; }; ui_account_row() { echo "  $1) [$2] $3 $4 $5"; }; S_ARROW=">"; CYN=""; RST=""; DIM=""; BOLD=""; GRN=""; GRY=""; }
say() { echo "$@"; }
tilde() { case "$1" in "$HOME"*) printf '~%s' "${1#$HOME}";; *) printf '%s' "$1";; esac; }
die() { echo "error: $*" >&2; exit 1; }

. "$SRC/package.sh"

# ---------- arguments ----------
while [ $# -gt 0 ]; do case "$1" in
  --skills) [ -n "${2:-}" ] || die "--skills needs a list (a,b | all | none)"; SKILLS_ARG="$2"; shift;;
  --dry-run) DRY=1;; --yes|-y) YES=1;; --no-bypass) OPT_BYPASS=0;; --safe) OPT_BYPASS=safe;; --no-path) OPT_PATH=0;; --no-trust) OPT_TRUST=0;; --statusline) OPT_STATUSLINE=1;; --no-statusline) OPT_STATUSLINE=0;; --uninstall) MODE=uninstall;; --list) MODE=list;; --check) MODE=check;; --fix) FIX=1;;
  --name) [ -n "${2:-}" ] || die "--name needs DIR=NAME"; OVERS="$OVERS
${2%%=*}=${2#*=}"; shift;;
  --claude-dir) [ -n "${2:-}" ] || die "--claude-dir needs a path"; CLAUDE_LIST="$CLAUDE_LIST
$2"; shift;;
  --codex-dir) [ -n "${2:-}" ] || die "--codex-dir needs a path"; CODEX_LIST="$CODEX_LIST
$2"; shift;;
  --kiro-dir) [ -n "${2:-}" ] || die "--kiro-dir needs a path"; KIRO_LIST="$KIRO_LIST
$2"; shift;;
  --agy-dir) [ -n "${2:-}" ] || die "--agy-dir needs a path (e.g. ~/.gemini/antigravity-cli)"; AGY_LIST="$AGY_LIST
$2"; shift;;
  --cursor-dir) [ -n "${2:-}" ] || die "--cursor-dir needs a path (e.g. ~/.cursor)"; CURSOR_LIST="$CURSOR_LIST
$2"; shift;;
  --copilot-dir) [ -n "${2:-}" ] || die "--copilot-dir needs a path (e.g. ~/.copilot)"; COPILOT_LIST="$COPILOT_LIST
$2"; shift;;
  --opencode-workers) [[ "${2:-}" =~ ^[0-9]+$ ]] && [ "$2" -ge 1 ] && [ "$2" -le 32 ] || die "--opencode-workers needs a number 1-32"; OC_WORKERS="$2"; shift;;
  --opencode-dir) [ -n "${2:-}" ] || die "--opencode-dir needs a path (e.g. ~/.opencode)"; OPENCODE_LIST="$OPENCODE_LIST
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
$d"; elif [ "$1" = codex ]; then has_line "$CODEX_LIST" "$d" || CODEX_LIST="$CODEX_LIST
$d"; elif [ "$1" = antigravity ]; then has_line "$AGY_LIST" "$d" || AGY_LIST="$AGY_LIST
$d"; elif [ "$1" = cursor ]; then has_line "$CURSOR_LIST" "$d" || CURSOR_LIST="$CURSOR_LIST
$d"; elif [ "$1" = copilot ]; then has_line "$COPILOT_LIST" "$d" || COPILOT_LIST="$COPILOT_LIST
$d";elif [ "$1" = opencode ]; then has_line "$OPENCODE_LIST" "$d" || OPENCODE_LIST="$OPENCODE_LIST
$d"; else has_line "$KIRO_LIST" "$d" || KIRO_LIST="$KIRO_LIST
$d"; fi; }
# normalize user-given dirs
tmp="$CLAUDE_LIST"; CLAUDE_LIST=""; while IFS= read -r d; do [ -n "$d" ] && add_dir claude "$d"; done <<EOF2
$tmp
EOF2
tmp="$CODEX_LIST"; CODEX_LIST=""; while IFS= read -r d; do [ -n "$d" ] && add_dir codex "$d"; done <<EOF2
$tmp
EOF2
tmp="$KIRO_LIST"; KIRO_LIST=""; while IFS= read -r d; do [ -n "$d" ] && add_dir kiro "$d"; done <<EOF2
$tmp
EOF2
tmp="$AGY_LIST"; AGY_LIST=""; while IFS= read -r d; do [ -n "$d" ] && add_dir antigravity "$d"; done <<EOF2
$tmp
EOF2
tmp="$CURSOR_LIST"; CURSOR_LIST=""; while IFS= read -r d; do [ -n "$d" ] && add_dir cursor "$d"; done <<EOF2
$tmp
EOF2
tmp="$COPILOT_LIST"; COPILOT_LIST=""; while IFS= read -r d; do [ -n "$d" ] && add_dir copilot "$d"; done <<EOF2
$tmp
EOF2
tmp="$OPENCODE_LIST"; OPENCODE_LIST=""; while IFS= read -r d; do [ -n "$d" ] && add_dir opencode "$d"; done <<EOF2
$tmp
EOF2
# default folders and ~/.claude-* / ~/.codex-* by name pattern
for d in "$HOME/.claude" "$HOME"/.claude-*; do
  [ -d "$d" ] || continue
  for m in settings.json .credentials.json projects commands skills; do [ -e "$d/$m" ] && { add_dir claude "$d"; break; }; done; done
for d in "$HOME/.codex" "$HOME"/.codex-*; do
  [ -d "$d" ] || continue
  for m in auth.json config.toml hooks.json sessions; do [ -e "$d/$m" ] && { add_dir codex "$d"; break; }; done; done
if command -v kiro-cli >/dev/null 2>&1 || [ -x "$HOME/.local/bin/kiro-cli" ] || [ -d "$HOME/.kiro/sessions" ]; then add_dir kiro "$HOME/.kiro"; fi
# Google Antigravity: one account per HOME (~/.gemini/antigravity-cli); the `agy` CLI keeps its sign-in in the system, not in that folder
if command -v agy >/dev/null 2>&1 || [ -x "$HOME/.local/bin/agy" ] || [ -d "$HOME/.gemini/antigravity-cli" ]; then [ "$DRY" = 1 ] || mkdir -p "$HOME/.gemini/antigravity-cli" 2>/dev/null || true; add_dir antigravity "$HOME/.gemini/antigravity-cli"; fi
# Cursor CLI (binary `cursor-agent`; never the bare `agent`) and GitHub Copilot CLI (`copilot`): one account per HOME (~/.cursor, ~/.copilot)
if command -v cursor-agent >/dev/null 2>&1 || [ -x "$HOME/.local/bin/cursor-agent" ] || [ -d "$HOME/.cursor/chats" ]; then [ -d "$HOME/.cursor" ] && add_dir cursor "$HOME/.cursor"; fi
if command -v copilot >/dev/null 2>&1 || [ -x "$HOME/.local/bin/copilot" ] || [ -d "$HOME/.copilot" ]; then [ -d "$HOME/.copilot" ] && add_dir copilot "$HOME/.copilot"; fi
# OpenCode: ONE install (~/.local/share/opencode/auth.json) shared by N workers; each worker is a marker folder ~/.opencode-1, ~/.opencode-2, ...
# (they hold `provider`=opencode, AGENTS.md and the skill). --opencode-workers N creates the first N markers.
if [ "$OC_WORKERS" -gt 0 ] && [ "$DRY" = 0 ]; then i=1; while [ "$i" -le "$OC_WORKERS" ]; do mkdir -p "$HOME/.opencode-$i"; i=$((i+1)); done; fi
for d in "$HOME"/.opencode-*; do [ -d "$d" ] && add_dir opencode "$d"; done
if [ -z "$OPENCODE_LIST" ] && [ "${BRIDGE_OPENCODE_AUTO:-1}" != 0 ] && { command -v opencode >/dev/null 2>&1 || [ -x "$HOME/.local/bin/opencode" ]; } && [ "$DRY" = 0 ]; then mkdir -p "$HOME/.opencode-1"; add_dir opencode "$HOME/.opencode-1"; fi
# current environment
[ -n "${CLAUDE_CONFIG_DIR:-}" ] && add_dir claude "$CLAUDE_CONFIG_DIR"
[ -n "${CODEX_HOME:-}" ] && add_dir codex "$CODEX_HOME"
[ -n "${KIRO_HOME:-}" ] && add_dir kiro "$KIRO_HOME"
# aliases / exports in shell startup files
for rc in "$HOME/.bashrc" "$HOME/.bash_aliases" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.zshenv" "$HOME/.config/fish/config.fish"; do
  [ -f "$rc" ] || continue
  for v in CLAUDE_CONFIG_DIR CODEX_HOME KIRO_HOME; do
    kind=claude; [ "$v" = CODEX_HOME ] && kind=codex; [ "$v" = KIRO_HOME ] && kind=kiro
    while IFS= read -r val; do [ -n "$val" ] && add_dir "$kind" "$val"; done <<EOF2
$(grep -v '^[[:space:]]*#' "$rc" | grep -Eo "$v[= ][^[:space:];&|)]+" | sed -E "s/^$v[= ]//")
EOF2
  done; done
CLAUDE_LIST="$(printf '%s\n' "$CLAUDE_LIST" | sed '/^$/d' | sort -u)"; CODEX_LIST="$(printf '%s\n' "$CODEX_LIST" | sed '/^$/d' | sort -u)"; KIRO_LIST="$(printf '%s\n' "$KIRO_LIST" | sed '/^$/d' | sort -u)"; AGY_LIST="$(printf '%s\n' "$AGY_LIST" | sed '/^$/d' | sort -u)"; CURSOR_LIST="$(printf '%s\n' "$CURSOR_LIST" | sed '/^$/d' | sort -u)"; COPILOT_LIST="$(printf '%s\n' "$COPILOT_LIST" | sed '/^$/d' | sort -u)"; OPENCODE_LIST="$(printf '%s\n' "$OPENCODE_LIST" | sed '/^$/d' | sort -V)"

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
while IFS= read -r d; do [ -n "$d" ] && assign "$d" claude; done <<EOF2
$CLAUDE_LIST
EOF2
while IFS= read -r d; do [ -n "$d" ] && assign "$d" codex; done <<EOF2
$CODEX_LIST
EOF2
while IFS= read -r d; do [ -n "$d" ] && assign "$d" kiro; done <<EOF2
$KIRO_LIST
EOF2
while IFS= read -r d; do [ -n "$d" ] && assign "$d" agy; done <<EOF2
$AGY_LIST
EOF2
while IFS= read -r d; do [ -n "$d" ] && assign "$d" cursor; done <<EOF2
$CURSOR_LIST
EOF2
while IFS= read -r d; do [ -n "$d" ] && assign "$d" copilot; done <<EOF2
$COPILOT_LIST
EOF2
while IFS= read -r d; do [ -n "$d" ] && assign "$d" opencode; done <<EOF2
$OPENCODE_LIST
EOF2

if [ "$MODE" = list ]; then
  say "system: $OS"
  while IFS= read -r d; do [ -n "$d" ] && say "claude  $(get_name "$d")  $d"; done <<EOF2
$CLAUDE_LIST
EOF2
  while IFS= read -r d; do [ -n "$d" ] && say "codex   $(get_name "$d")  $d"; done <<EOF2
$CODEX_LIST
EOF2
  while IFS= read -r d; do [ -n "$d" ] && say "kiro    $(get_name "$d")  $d"; done <<EOF2
$KIRO_LIST
EOF2
  while IFS= read -r d; do [ -n "$d" ] && say "agy     $(get_name "$d")  $d"; done <<EOF2
$AGY_LIST
EOF2
  while IFS= read -r d; do [ -n "$d" ] && say "cursor  $(get_name "$d")  $d"; done <<EOF2
$CURSOR_LIST
EOF2
  while IFS= read -r d; do [ -n "$d" ] && say "copilot    $(get_name "$d")  $d"; done <<EOF2
$COPILOT_LIST
EOF2
  while IFS= read -r d; do [ -n "$d" ] && say "opencode    $(get_name "$d")  $d"; done <<EOF2
$OPENCODE_LIST
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
MS_TOP=0; MS_DRAWN=0; MS_BACK=0; MS_CAN_BACK=0
ms_geom() { MS_ROWS="$(tput lines 2>/dev/null || echo 24)"; MS_COLS="$(tput cols 2>/dev/null || echo 80)"
  case "$MS_ROWS" in ''|*[!0-9]*) MS_ROWS=24;; esac; case "$MS_COLS" in ''|*[!0-9]*) MS_COLS=80;; esac
  MS_VIS=$((MS_ROWS - 15)); [ $MS_VIS -lt 5 ] && MS_VIS=5; [ $MS_VIS -gt $MS_N ] && MS_VIS=$MS_N; return 0; }
ms_clamp() { [ $MS_CUR -lt $MS_TOP ] && MS_TOP=$MS_CUR; [ $MS_CUR -ge $((MS_TOP + MS_VIS)) ] && MS_TOP=$((MS_CUR - MS_VIS + 1)); [ $MS_TOP -lt 0 ] && MS_TOP=0; return 0; }
ms_draw() { local i p m plain lab pad max sub end lw=0 n sel=0
  ms_geom; ms_clamp; end=$((MS_TOP + MS_VIS)); [ $end -gt $MS_N ] && end=$MS_N; MS_DRAWN=0
  i=0; while [ $i -lt $MS_N ]; do n=${#MS_L[$i]}; [ "${MS_F[$i]:-0}" = 1 ] && n=$((n+2)); [ $n -gt $lw ] && lw=$n
    [ "${MS_ON[$i]}" = 1 ] && { [ $MS_ALL = 1 ] && [ $i = 0 ] || sel=$((sel+1)); }; i=$((i+1)); done
  [ $lw -gt 30 ] && lw=30
  i=$MS_TOP; while [ $i -lt $end ]; do
    if [ "${MS_ON[$i]}" = 1 ]; then m="${GRN}${S_ON}${RST}"; else m="${GRY}${S_OFF}${RST}"; fi
    plain="${MS_L[$i]}"; [ "${MS_F[$i]:-0}" = 1 ] && plain="★ $plain"
    [ ${#plain} -gt $lw ] && plain="${plain:0:$((lw-1))}…"
    pad=$((lw - ${#plain})); [ $pad -lt 0 ] && pad=0
    lab="$plain"; [ "${MS_F[$i]:-0}" = 1 ] && lab="${MAG}${plain}${RST}"; [ $MS_ALL = 1 ] && [ $i = 0 ] && lab="${CYN}${plain}${RST}"
    if [ $i -eq $MS_CUR ]; then p="${CYN}${S_ARROW}${RST}"; lab="${BOLD}${lab}${RST}"; else p=" "; fi
    max=$((MS_COLS - lw - 12)); sub="${MS_S[$i]}"
    if [ $max -lt 8 ]; then sub=""; elif [ ${#sub} -gt $max ]; then sub="${sub:0:$((max-1))}…"; fi
    printf '\033[2K\r  %s %s  %s%*s  %s%s%s\n' "$p" "$m" "$lab" "$pad" "" "$DIM" "$sub" "$RST"; MS_DRAWN=$((MS_DRAWN+1)); i=$((i+1)); done
  if [ $MS_ALL = 1 ] || [ $MS_N -gt $MS_VIS ]; then
    printf '\033[2K\r\n\033[2K\r  %s%s%s%s selected%s   %s%d/%d%s\n' "$GRN" "$BOLD" "$sel" "$RST$DIM" "$RST" "$DIM" $((MS_CUR+1)) $MS_N "$RST"; MS_DRAWN=$((MS_DRAWN+2)); fi; }
MS_ALL=0
ms_allsync() { [ $MS_ALL = 1 ] || return 0; local i all=1 v
  if [ $MS_CUR = 0 ]; then v="${MS_ON[0]}"; i=1; while [ $i -lt $MS_N ]; do MS_ON[$i]=$v; i=$((i+1)); done
  else i=1; while [ $i -lt $MS_N ]; do [ "${MS_ON[$i]}" = 1 ] || all=0; i=$((i+1)); done; MS_ON[0]=$all; fi; }
# bash 3.2 (macOS) applies `read -s` to stdin, not to -u 3: switch the terminal off echo / line mode explicitly
MS_STTY=""
ms_raw_on() { [ -n "$MS_STTY" ] || trap 'ms_raw_off; ui_cursor_on' EXIT INT TERM; MS_STTY="$(stty -g <&3 2>/dev/null || true)"; stty -echo -icanon min 1 time 0 <&3 2>/dev/null || true; }
ms_raw_off() { if [ -n "$MS_STTY" ]; then stty "$MS_STTY" <&3 2>/dev/null || stty sane <&3 2>/dev/null || true; else stty echo icanon <&3 2>/dev/null || true; fi; }
ms_run() { local k rest first=1 i
  MS_CUR=0; MS_TOP=0; MS_EXTRA=0; MS_DRAWN=0; MS_BACK=0; ui_cursor_off
  ms_raw_on
  # zsh/macOS terminals may leave the keypad in application mode (arrows arrive as ESC O A); force normal mode
  [ $UI_COLOR = 1 ] && printf '\033[?1l\033>' >&2
  while :; do
    if [ $first = 0 ] && [ $((MS_DRAWN + MS_EXTRA)) -gt 0 ]; then printf '\033[%dA\033[J' $((MS_DRAWN + MS_EXTRA)); fi
    first=0; MS_EXTRA=0; ms_draw
    IFS= read -rsn1 -u 3 k || k=""
    case "$k" in
      "") break;;
      " ") [ $MS_N -gt 0 ] && { [ "${MS_ON[$MS_CUR]}" = 1 ] && MS_ON[$MS_CUR]=0 || MS_ON[$MS_CUR]=1; ms_allsync; };;
      $'\033') rest=""; IFS= read -rsn1 -t 1 -u 3 k2 || k2=""; if [ -n "$k2" ]; then IFS= read -rsn1 -t 1 -u 3 k3 || k3=""; rest="$k2$k3"; fi
        case "$rest" in "[A"|"OA") [ $MS_CUR -gt 0 ] && MS_CUR=$((MS_CUR-1));; "[B"|"OB") [ $MS_CUR -lt $((MS_N-1)) ] && MS_CUR=$((MS_CUR+1));; esac;;
      k|K) [ $MS_CUR -gt 0 ] && MS_CUR=$((MS_CUR-1));;
      j|J) [ $MS_CUR -lt $((MS_N-1)) ] && MS_CUR=$((MS_CUR+1));;
      b|B) if [ $MS_CAN_BACK = 1 ]; then MS_BACK=1; break; fi;;
      a) i=0; while [ $i -lt $MS_N ]; do MS_ON[$i]=1; i=$((i+1)); done;;
      n) i=0; while [ $i -lt $MS_N ]; do MS_ON[$i]=0; i=$((i+1)); done; ms_allsync;;
      *) [ -n "$MS_CB" ] && "$MS_CB" "$k";;
    esac
  done
  ms_raw_off; ui_cursor_on; return 0; }
hint() { printf '  %s%s%s\n' "$DIM" "$1" "$RST"; }
acc_refresh() { local i=0; while [ $i -lt $MS_N ]; do MS_L[$i]="$(get_name "${ACC_DIR[$i]}")"; MS_S[$i]="${ACC_KIND[$i]}   $(tilde "${ACC_DIR[$i]}")"; i=$((i+1)); done; }
acc_cb() { case "$1" in
  r) ms_raw_off; ui_cursor_on; printf '\n  %s%s%s new name for %s: ' "$CYN" "$S_ARROW" "$RST" "${MS_L[$MS_CUR]}"; IFS= read -r REPLY <&3 || REPLY=""; ui_cursor_off; ms_raw_on; MS_EXTRA=2
     case "$REPLY" in ""|*[!A-Za-z0-9_-]*) ;; *) if printf '%s\n' "$MAP" | awk -F= -v k="${ACC_DIR[$MS_CUR]}" -v v="$REPLY" '$1!=k && $2==v{f=1} END{exit !f}'; then :; else set_name "${ACC_DIR[$MS_CUR]}" "$REPLY"; acc_refresh; fi;; esac;;
  +) ms_raw_off; ui_cursor_on; printf '\n  %s%s%s type (claude/codex/kiro/agy/cursor/copilot/opencode): ' "$CYN" "$S_ARROW" "$RST"; IFS= read -r kind <&3 || kind=""
     printf '  %s%s%s folder: ' "$CYN" "$S_ARROW" "$RST"; IFS= read -r REPLY <&3 || REPLY=""; ui_cursor_off; ms_raw_on; MS_EXTRA=3
     local p; p="$(norm "$REPLY")" || p=""
     [ "$kind" = agy ] && kind=antigravity
     if { [ "$kind" = claude ] || [ "$kind" = codex ] || [ "$kind" = kiro ] || [ "$kind" = antigravity ] || [ "$kind" = cursor ] || [ "$kind" = copilot ] || [ "$kind" = opencode ]; } && [ -n "$p" ] && [ -d "$p" ]; then
       assign "$p" "$([ "$kind" = claude ] && echo claude || { [ "$kind" = antigravity ] && echo agy || echo "$kind"; })"
       ACC_KIND[$MS_N]="$kind"; ACC_DIR[$MS_N]="$p"; MS_ON[$MS_N]=1; MS_F[$MS_N]=0; MS_N=$((MS_N+1)); acc_refresh; fi;;
  esac; }
keys() { local o="" k; for k in "$@"; do o="$o${CYN}${BOLD}${k%% *}${RST} ${DIM}${k#* }${RST}   "; done; printf '  %s\n' "$o"; }
stepper() { local cur="$1" i=0 o="" nm sep="${DIM}${B_H}${B_H}${RST}"
  for nm in Packages Accounts agent-bridge Confirm; do i=$((i+1))
    if [ $i -lt $cur ]; then o="$o${GRN}${S_OK} ${nm}${RST}"
    elif [ $i -eq $cur ]; then o="$o${BOLD}${MAG}${S_ON} ${nm}${RST}"
    else o="$o${GRY}${S_OFF} ${nm}${RST}"; fi
    [ $i -lt 4 ] && o="$o $sep "; done
  printf '  %s\n' "$o"; }
menu_screen() { local n="$1"; shift; UI_FAST=1; ui_clear; ui_banner; stepper "$n"; echo; keys "$@"; echo; }
run_menu() {
  exec 3< "$TTY"
  local i d step=1 back="b back"
  ACC_KIND=(); ACC_DIR=(); MS_L=(); MS_S=(); MS_ON=(); MS_F=(); MS_N=0
  while IFS= read -r d; do [ -n "$d" ] && { ACC_KIND[$MS_N]=claude; ACC_DIR[$MS_N]="$d"; MS_ON[$MS_N]=1; MS_N=$((MS_N+1)); }; done <<EOF2
$CLAUDE_LIST
EOF2
  while IFS= read -r d; do [ -n "$d" ] && { ACC_KIND[$MS_N]=codex; ACC_DIR[$MS_N]="$d"; MS_ON[$MS_N]=1; MS_N=$((MS_N+1)); }; done <<EOF2
$CODEX_LIST
EOF2
  while IFS= read -r d; do [ -n "$d" ] && { ACC_KIND[$MS_N]=kiro; ACC_DIR[$MS_N]="$d"; MS_ON[$MS_N]=1; MS_N=$((MS_N+1)); }; done <<EOF2
$KIRO_LIST
EOF2
  while IFS= read -r d; do [ -n "$d" ] && { ACC_KIND[$MS_N]=antigravity; ACC_DIR[$MS_N]="$d"; MS_ON[$MS_N]=1; MS_N=$((MS_N+1)); }; done <<EOF2
$AGY_LIST
EOF2
  while IFS= read -r d; do [ -n "$d" ] && { ACC_KIND[$MS_N]=cursor; ACC_DIR[$MS_N]="$d"; MS_ON[$MS_N]=1; MS_N=$((MS_N+1)); }; done <<EOF2
$CURSOR_LIST
EOF2
  while IFS= read -r d; do [ -n "$d" ] && { ACC_KIND[$MS_N]=copilot; ACC_DIR[$MS_N]="$d"; MS_ON[$MS_N]=1; MS_N=$((MS_N+1)); }; done <<EOF2
$COPILOT_LIST
EOF2
  while IFS= read -r d; do [ -n "$d" ] && { ACC_KIND[$MS_N]=opencode; ACC_DIR[$MS_N]="$d"; MS_ON[$MS_N]=1; MS_N=$((MS_N+1)); }; done <<EOF2
$OPENCODE_LIST
EOF2
  acc_refresh
  ACC_N=$MS_N; ACC_ONS=("${MS_ON[@]}")
  PK_ON=(); PK_L=("agent-bridge"); PK_S=("Claude Code + Codex + Kiro + Antigravity + Cursor + Copilot + OpenCode sessions that talk to each other"); PK_ON[0]=1
  i=0; while [ $i -lt ${#SK_NAMES[@]} ]; do PK_L[$((i+1))]="${SK_NAMES[$i]}"; PK_S[$((i+1))]="${SK_DESC[$i]}"; PK_ON[$((i+1))]=0; i=$((i+1)); done
  OPT_ON=(1 1 1 1)
  info_wait() { local k; ui_cursor_off; while :; do IFS= read -rsn1 -u 3 k || k=""; case "$k" in "") ui_cursor_on; return 0;; b|B) ui_cursor_on; MS_BACK=1; return 0;; e|E) if [ "${MS_EDITABLE:-0}" = 1 ]; then ui_cursor_on; MS_EDIT=1; return 0; fi;; esac; done; }
  info_row() { printf '    %s%s%s  %s%-9s%s %s%-7s%s %s%s%s\n' "$GRN" "$S_OK" "$RST" "$BOLD" "$1" "$RST" "$BLU" "$2" "$RST" "$CYN" "$3" "$RST"; }
  while :; do
    case $step in
    1) # --- packages (select) ---
      MS_L=("all" "${PK_L[@]}"); MS_S=("select every package" "${PK_S[@]}"); MS_ON=(0 "${PK_ON[@]}"); MS_F=(0 1); MS_N=$((${#PK_L[@]}+1)); MS_ALL=1
      i=1; MS_ON[0]=1; while [ $i -lt $MS_N ]; do [ "${MS_ON[$i]}" = 1 ] || MS_ON[0]=0; i=$((i+1)); done
      menu_screen 1 "↑↓/jk move" "space select" "a all" "n none" "enter continue"
      MS_CAN_BACK=0; ms_run; MS_ALL=0
      PK_ON=("${MS_ON[@]:1}"); PKG_AB="${MS_ON[1]}"; SEL_SKILLS=""; i=2
      while [ $i -lt $MS_N ]; do [ "${MS_ON[$i]}" = 1 ] && SEL_SKILLS="$SEL_SKILLS ${MS_L[$i]}"; i=$((i+1)); done
      SEL_SKILLS="${SEL_SKILLS# }"
      step=2;;
    2) # --- accounts (info) ---
      menu_screen 2 "e edit" "b back" "enter continue"; echo "  ${DIM}Detected accounts; all of them will be configured${RST}"; echo
      CLAUDE_LIST=""; CODEX_LIST=""; KIRO_LIST=""; AGY_LIST=""; CURSOR_LIST=""; COPILOT_LIST=""; OPENCODE_LIST=""; i=0
      while [ $i -lt $ACC_N ]; do
        [ "${ACC_ONS[$i]}" = 1 ] || { i=$((i+1)); continue; }
        info_row "$(get_name "${ACC_DIR[$i]}")" "${ACC_KIND[$i]}" "$(tilde "${ACC_DIR[$i]}")"
        case "${ACC_KIND[$i]}" in claude) CLAUDE_LIST="$CLAUDE_LIST
${ACC_DIR[$i]}";; codex) CODEX_LIST="$CODEX_LIST
${ACC_DIR[$i]}";; kiro) KIRO_LIST="$KIRO_LIST
${ACC_DIR[$i]}";; antigravity) AGY_LIST="$AGY_LIST
${ACC_DIR[$i]}";; cursor) CURSOR_LIST="$CURSOR_LIST
${ACC_DIR[$i]}";; copilot) COPILOT_LIST="$COPILOT_LIST
${ACC_DIR[$i]}";;opencode) OPENCODE_LIST="$OPENCODE_LIST
${ACC_DIR[$i]}";; esac; i=$((i+1)); done
      echo; MS_BACK=0; MS_EDIT=0; MS_EDITABLE=1; info_wait; MS_EDITABLE=0
      [ $MS_BACK = 1 ] && { step=1; continue; }
      if [ $MS_EDIT = 1 ]; then
        MS_L=(); MS_S=(); MS_ON=("${ACC_ONS[@]}"); MS_F=(); MS_N=$ACC_N; acc_refresh
        menu_screen 2 "↑↓/jk move" "space select" "r rename" "+ add folder" "enter done"
        MS_CAN_BACK=0; MS_CB=acc_cb; ms_run; MS_CB=""; ACC_N=$MS_N; ACC_ONS=("${MS_ON[@]}"); continue; fi
      if [ "$PKG_AB" = 1 ]; then step=3; else step=4; fi;;
    3) # --- agent-bridge options (info) ---
      menu_screen 3 "b back" "enter continue"; echo "  ${DIM}What agent-bridge will set up${RST}"; echo
      for d in "Skill + /admin /agent commands|how sessions learn the commands" "Message hook|delivers messages between sessions" "Auto-approve Codex hooks|no /hooks review needed in Codex" "Status line data for /dashboard|keeps your status line, also saves its numbers" "Headless workers in bypass mode|no permission prompts for orders" "Put agent/admin on PATH|~/.local/bin"; do
        printf '    %s%s%s  %-34s %s%s%s\n' "$GRN" "$S_OK" "$RST" "${d%%|*}" "$DIM" "${d#*|}" "$RST"; done
      echo; MS_BACK=0; info_wait
      [ $MS_BACK = 1 ] && { step=2; continue; }
      step=4;;
    4) # --- confirm ---
      local nc nx nk na ncu ncp nop pk opts; nc=$(printf '%s\n' "$CLAUDE_LIST" | sed '/^$/d' | wc -l | tr -d ' '); nx=$(printf '%s\n' "$CODEX_LIST" | sed '/^$/d' | wc -l | tr -d ' '); nk=$(printf '%s\n' "$KIRO_LIST" | sed '/^$/d' | wc -l | tr -d ' '); na=$(printf '%s\n' "$AGY_LIST" | sed '/^$/d' | wc -l | tr -d ' '); ncu=$(printf '%s\n' "$CURSOR_LIST" | sed '/^$/d' | wc -l | tr -d ' '); ncp=$(printf '%s\n' "$COPILOT_LIST" | sed '/^$/d' | wc -l | tr -d ' '); nop=$(printf '%s\n' "$OPENCODE_LIST" | sed '/^$/d' | wc -l | tr -d ' ')
      NACC=$((nc + nx + nk + na + ncu + ncp + nop)); pk="$SEL_SKILLS"; [ "$PKG_AB" = 1 ] && pk="agent-bridge $pk"; pk="$(printf '%s' "$pk" | sed 's/ *$//; s/ /, /g')"; [ -n "$pk" ] || pk="none"
      local npk; npk=$(printf '%s' "$pk" | tr ',' '\n' | sed '/^ *$/d' | wc -l | tr -d ' '); [ ${#pk} -gt 58 ] && pk="${pk:0:55}…  ${DIM}($npk packages)${RST}"
      menu_screen 4 "enter install" "n back"
      opts="skill+commands, hook"; [ "$OPT_STATUSLINE" = 1 ] && opts="$opts, status line data"; [ "$OPT_TRUST" = 1 ] && opts="$opts, auto-approve Codex hooks"; [ "$OPT_BYPASS" = 1 ] && opts="$opts, bypass workers"; [ "$OPT_BYPASS" = safe ] && opts="$opts, safe-mode workers"; [ "$OPT_PATH" = 1 ] && opts="$opts, PATH"
      sl=("${DIM}Accounts     ${RST}${BOLD}$NACC${RST}  ${DIM}($nc claude · $nx codex · $nk kiro · $na agy · $ncu cursor · $ncp copilot · $nop opencode)${RST}" "${DIM}Packages     ${RST}$pk")
      [ "$PKG_AB" = 1 ] && sl+=("${DIM}agent-bridge ${RST}$opts")
      ui_box "Summary" "${sl[@]}"
      yn "Install now?" 1 && break
      if [ "$PKG_AB" = 1 ]; then step=3; else step=2; fi;;
    esac
  done
  MS_CAN_BACK=0; UI_FAST=""; ui_clear; ui_banner
  exec 3<&-
}
[ "$MODE" = install ] && ui_banner
if [ "$MODE" = install ] && [ $YES = 0 ] && [ $DRY = 0 ] && can_ask; then run_menu; fi

# ---------- generic helpers ----------
act() { if [ $DRY = 1 ]; then say "  [dry-run] $*"; else eval "$@"; fi; }
each() { local list="$1"; shift; while IFS= read -r d; do [ -n "$d" ] && "$@" "$d"; done <<EOF2
$list
EOF2
  return 0
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

# ---------- check ----------
BAD=0; QUIET=0
ok() { [ $QUIET = 1 ] || ui_okline "$1"; }; bad() { [ $QUIET = 1 ] || ui_failline "$1"; BAD=$((BAD+1)); }
chk_claude() { local d="$1" n; n="$(get_name "$d")"
  if jq -e '[.hooks[]?[]?.hooks[]?.command // ""] | any(contains("bridge-hook"))' "$d/settings.json" >/dev/null 2>&1; then ok "Claude  $n  hook"; else bad "Claude  $n  hook missing ($(tilde "$d"))"; fi
  if [ "$(jq -r '.env.BRIDGE_NAME // empty' "$d/settings.json" 2>/dev/null)" = "$n" ]; then ok "Claude  $n  name"; else bad "Claude  $n  BRIDGE_NAME not set"; fi
  if [ "$OPT_STATUSLINE" = 1 ]; then if [ "$(jq -r '.statusLine.command // empty' "$d/settings.json" 2>/dev/null)" = "$BR/bin/bridge-statusline" ]; then ok "Claude  $n  status line data"; else bad "Claude  $n  status line not wrapped (dashboard data)"; fi; fi
  if [ -f "$d/skills/agent-bridge/SKILL.md" ] && cmp -s "$d/skills/agent-bridge/SKILL.md" "$SRC/SKILL.md"; then ok "Claude  $n  skill up to date"; else bad "Claude  $n  skill missing or outdated"; fi; }
chk_codex() { local d="$1" n out; n="$(get_name "$d")"
  if jq -e '[.hooks[]?[]?.hooks[]?.command // ""] | any(contains("bridge-hook"))' "$d/hooks.json" >/dev/null 2>&1; then ok "Codex   $n  hook"; else bad "Codex   $n  hook missing ($(tilde "$d"))"; fi
  if [ "$OPT_TRUST" = 1 ] && command -v python3 >/dev/null 2>&1 && command -v codex >/dev/null 2>&1; then
    if out="$(python3 "$SRC/scripts/codex-trust-hooks" "$d" --check 2>&1)"; then ok "Codex   $n  hooks approved"; else bad "Codex   $n  $(printf '%s\n' "$out" | grep -c untrusted) hook(s) not approved: reinstall or run /hooks"; fi; fi
  if [ -f "$d/skills/agent-bridge/SKILL.md" ] && cmp -s "$d/skills/agent-bridge/SKILL.md" "$SRC/SKILL.md"; then ok "Codex   $n  skill up to date"; else bad "Codex   $n  skill missing or outdated"; fi; }
chk_kiro() { local d="$1" n; n="$(get_name "$d")"
  if [ -f "$d/steering/AGENTS.md" ] && grep -q 'BRIDGE-BEGIN' "$d/steering/AGENTS.md"; then ok "Kiro    $n  steering"; else bad "Kiro    $n  steering missing ($(tilde "$d"))"; fi
  if [ -f "$d/steering/agent-bridge.md" ] && cmp -s "$d/steering/agent-bridge.md" "$SRC/SKILL.md"; then ok "Kiro    $n  skill up to date"; else bad "Kiro    $n  skill missing or outdated"; fi; }
chk_antigravity() { local d="$1" n cfg; n="$(get_name "$d")"; cfg="$(agy_cfg "$d")"
  if [ -f "$cfg/AGENTS.md" ] && grep -q 'BRIDGE-BEGIN' "$cfg/AGENTS.md"; then ok "Agy     $n  global rules"; else bad "Agy     $n  global rules missing ($(tilde "$cfg"))"; fi
  if [ -f "$cfg/skills/agent-bridge/SKILL.md" ] && cmp -s "$cfg/skills/agent-bridge/SKILL.md" "$SRC/SKILL.md"; then ok "Agy     $n  skill up to date"; else bad "Agy     $n  skill missing or outdated"; fi; }
chk_cursor() { local d="$1" n; n="$(get_name "$d")"
  if [ -f "$d/skills/agent-bridge/SKILL.md" ] && cmp -s "$d/skills/agent-bridge/SKILL.md" "$SRC/SKILL.md"; then ok "Cursor  $n  skill up to date"; else bad "Cursor  $n  skill missing or outdated"; fi
  if cursor_agent_clash; then :; else bad "Cursor  $n  'agent' on PATH is Cursor's, not the bridge's: call cursor-agent and reinstall the bridge command (./install.sh)"; fi; }
chk_copilot() { local d="$1" n; n="$(get_name "$d")"
  if [ -f "$d/copilot-instructions.md" ] && grep -q 'BRIDGE-BEGIN' "$d/copilot-instructions.md"; then ok "Copilot    $n  copilot-instructions.md"; else bad "Copilot    $n  copilot-instructions.md block missing ($(tilde "$d"))"; fi
  if [ -f "$d/skills/agent-bridge/SKILL.md" ] && cmp -s "$d/skills/agent-bridge/SKILL.md" "$SRC/SKILL.md"; then ok "Copilot    $n  skill up to date"; else bad "Copilot    $n  skill missing or outdated"; fi; }
chk_opencode() { local d="$1" n; n="$(get_name "$d")"
  if [ -f "$d/AGENTS.md" ] && grep -q 'BRIDGE-BEGIN' "$d/AGENTS.md"; then ok "OpenCode    $n  AGENTS.md"; else bad "OpenCode    $n  AGENTS.md block missing ($(tilde "$d"))"; fi
  if [ -f "$d/skills/agent-bridge/SKILL.md" ] && cmp -s "$d/skills/agent-bridge/SKILL.md" "$SRC/SKILL.md"; then ok "OpenCode    $n  skill up to date"; else bad "OpenCode    $n  skill missing or outdated"; fi; }
chk_scripts() { local x; for x in agent admin bridge-hook bridge-runner bridge-send bridge-wait bridge-whoami bridge-provider bridge-agy-home bridge-account-home; do
    if [ -x "$BR/bin/$x" ]; then ok "script $x"; else bad "script $x missing or broken in $(tilde "$BR/bin")"; fi; done; }
# account_ok <claude|codex|kiro> <dir>: silently tells whether the account is already fully set up
account_ok() { local b=$BAD; QUIET=1; "chk_$1" "$2"; QUIET=0; local r=$((BAD - b)); BAD=$b; [ $r = 0 ]; }
upstream_newer() { command -v git >/dev/null 2>&1 && [ -d "$ROOT/.git" ] || return 1
  local lo re; lo="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)"; re="$(timeout 5 git -C "$ROOT" ls-remote origin HEAD 2>/dev/null | cut -f1)"; [ -n "$re" ] && [ "$re" != "$lo" ] || return 1
  git -C "$ROOT" cat-file -e "$re^{commit}" 2>/dev/null || return 0; ! git -C "$ROOT" merge-base --is-ancestor "$re" "$lo" 2>/dev/null; }
if [ "$MODE" = check ]; then
  ui_h "Check"; chk_scripts; SB=$BAD; FIX_CLAUDE=""; FIX_CODEX=""; FIX_KIRO=""; FIX_AGY=""; FIX_CURSOR=""; FIX_COPILOT=""; FIX_OPENCODE=""
  while IFS= read -r d; do [ -n "$d" ] || continue; b=$BAD; chk_claude "$d"; [ $BAD -gt $b ] && FIX_CLAUDE="$FIX_CLAUDE
$d"; done <<EOF2
$CLAUDE_LIST
EOF2
  while IFS= read -r d; do [ -n "$d" ] || continue; b=$BAD; chk_codex "$d"; [ $BAD -gt $b ] && FIX_CODEX="$FIX_CODEX
$d"; done <<EOF2
$CODEX_LIST
EOF2
  while IFS= read -r d; do [ -n "$d" ] || continue; b=$BAD; chk_kiro "$d"; [ $BAD -gt $b ] && FIX_KIRO="$FIX_KIRO
$d"; done <<EOF2
$KIRO_LIST
EOF2
  while IFS= read -r d; do [ -n "$d" ] || continue; b=$BAD; chk_antigravity "$d"; [ $BAD -gt $b ] && FIX_AGY="$FIX_AGY
$d"; done <<EOF2
$AGY_LIST
EOF2
  while IFS= read -r d; do [ -n "$d" ] || continue; b=$BAD; chk_cursor "$d"; [ $BAD -gt $b ] && FIX_CURSOR="$FIX_CURSOR
$d"; done <<EOF2
$CURSOR_LIST
EOF2
  while IFS= read -r d; do [ -n "$d" ] || continue; b=$BAD; chk_copilot "$d"; [ $BAD -gt $b ] && FIX_COPILOT="$FIX_COPILOT
$d"; done <<EOF2
$COPILOT_LIST
EOF2
  while IFS= read -r d; do [ -n "$d" ] || continue; b=$BAD; chk_opencode "$d"; [ $BAD -gt $b ] && FIX_OPENCODE="$FIX_OPENCODE
$d"; done <<EOF2
$OPENCODE_LIST
EOF2
  echo; upstream_newer && ui_warn "a newer version exists upstream: git pull, or re-run the one-line installer"
  if [ $BAD = 0 ]; then ui_info "everything looks fine"; exit 0; fi
  if [ $FIX = 1 ]; then ui_info "repairing $BAD problem(s)..."; MODE=install; YES=1
    if [ $SB -gt 0 ]; then :; else CLAUDE_LIST="$FIX_CLAUDE"; CODEX_LIST="$FIX_CODEX"; KIRO_LIST="$FIX_KIRO"; AGY_LIST="$FIX_AGY"; CURSOR_LIST="$FIX_CURSOR"; COPILOT_LIST="$FIX_COPILOT"; OPENCODE_LIST="$FIX_OPENCODE"; fi
  else ui_warn "$BAD problem(s): run ./install.sh to repair, or ./install.sh --check --fix"; exit 1; fi; fi
# ---------- uninstall ----------
un_claude() { say "uninstalling Claude: $1"; ab_un_claude "$1"; remove_skills "$1"; }
un_codex() { say "uninstalling Codex: $1"; ab_un_codex "$1"; remove_skills "$1"; }
un_kiro() { say "uninstalling Kiro: $1"; ab_un_kiro "$1"; remove_skills "$1"; }
un_cursor() { say "uninstalling Cursor: $1"; ab_un_cursor "$1"; remove_skills "$1"; }
un_copilot() { say "uninstalling Copilot: $1"; ab_un_copilot "$1"; remove_skills "$1"; }
un_opencode() { say "uninstalling OpenCode: $1"; ab_un_opencode "$1"; remove_skills "$1"; }
un_agy() { say "uninstalling Antigravity: $1"; ab_un_agy "$1"; remove_skills "$(agy_cfg "$1")"; }
if [ "$MODE" = uninstall ]; then each "$CLAUDE_LIST" un_claude; each "$CODEX_LIST" un_codex; each "$KIRO_LIST" un_kiro; each "$AGY_LIST" un_agy; each "$CURSOR_LIST" un_cursor; each "$COPILOT_LIST" un_copilot; each "$OPENCODE_LIST" un_opencode
  say "done. agent-bridge and the extra skills this installer added were removed. The mailbox $BR (messages, names.conf) is kept."; exit 0; fi

# ---------- install ----------
in_claude() { [ "$PKG_AB" = 1 ] && ab_install_claude "$1"; install_skills "$1"; return 0; }
in_codex() { [ "$PKG_AB" = 1 ] && ab_install_codex "$1"; install_skills "$1"; return 0; }
in_kiro() { [ "$PKG_AB" = 1 ] && ab_install_kiro "$1"; install_skills "$1"; return 0; }
in_agy() { [ "$PKG_AB" = 1 ] && ab_install_agy "$1"; install_skills "$(agy_cfg "$1")"; return 0; }
in_cursor() { [ "$PKG_AB" = 1 ] && ab_install_cursor "$1"; install_skills "$1"; return 0; }
in_copilot() { [ "$PKG_AB" = 1 ] && ab_install_copilot "$1"; install_skills "$1"; return 0; }
in_opencode() { [ "$PKG_AB" = 1 ] && ab_install_opencode "$1"; install_skills "$1"; return 0; }
step_cursor() { ui_run "${BOLD}Cursor${RST}  ${GRN}$(printf '%-9s' "$(get_name "$1")")${RST} ${CYN}$(tilde "$1")${RST}" in_cursor "$1"; }
step_copilot() { ui_run "${BOLD}Copilot${RST}    ${GRN}$(printf '%-9s' "$(get_name "$1")")${RST} ${CYN}$(tilde "$1")${RST}" in_copilot "$1"; }
step_opencode() { ui_run "${BOLD}OpenCode${RST}    ${GRN}$(printf '%-9s' "$(get_name "$1")")${RST} ${CYN}$(tilde "$1")${RST}" in_opencode "$1"; }
step_claude() { ui_run "${BOLD}Claude${RST}  ${GRN}$(printf '%-9s' "$(get_name "$1")")${RST} ${CYN}$(tilde "$1")${RST}" in_claude "$1"; }
step_codex() { ui_run "${BOLD}Codex${RST}   ${GRN}$(printf '%-9s' "$(get_name "$1")")${RST} ${CYN}$(tilde "$1")${RST}" in_codex "$1"; }
step_agy() { ui_run "${BOLD}Agy${RST}     ${GRN}$(printf '%-9s' "$(get_name "$1")")${RST} ${CYN}$(tilde "$1")${RST}" in_agy "$1"; }
step_kiro() { ui_run "${BOLD}Kiro${RST}    ${GRN}$(printf '%-9s' "$(get_name "$1")")${RST} ${CYN}$(tilde "$1")${RST}" in_kiro "$1"; }

# remember which accounts were already fully set up (shown as "up to date" at the end)
UPTODATE=""; if [ $DRY = 0 ] && [ "$PKG_AB" = 1 ] && command -v jq >/dev/null 2>&1; then
  for d in $CLAUDE_LIST; do account_ok claude "$d" && UPTODATE="$UPTODATE|$d"; done; for d in $CODEX_LIST; do account_ok codex "$d" && UPTODATE="$UPTODATE|$d"; done; for d in $KIRO_LIST; do account_ok kiro "$d" && UPTODATE="$UPTODATE|$d"; done; for d in $AGY_LIST; do account_ok antigravity "$d" && UPTODATE="$UPTODATE|$d"; done; for d in $CURSOR_LIST; do account_ok cursor "$d" && UPTODATE="$UPTODATE|$d"; done; for d in $COPILOT_LIST; do account_ok copilot "$d" && UPTODATE="$UPTODATE|$d"; done; for d in $OPENCODE_LIST; do account_ok opencode "$d" && UPTODATE="$UPTODATE|$d"; done; fi
ui_h "Installing"
if [ "$PKG_AB" != 1 ]; then :; elif [ $DRY = 1 ]; then :; else ui_run "${BOLD}Scripts${RST}    ${CYN}$(tilde "$BR/bin")${RST}" do_scripts; fi
if [ "$PKG_AB" = 1 ] && [ $OPT_PATH = 1 ] && [ $DRY = 0 ]; then ui_run "Commands on PATH  ${DIM}~/.local/bin${RST}" do_path; fi
each "$CLAUDE_LIST" step_claude; each "$CODEX_LIST" step_codex; each "$KIRO_LIST" step_kiro; each "$AGY_LIST" step_agy; each "$CURSOR_LIST" step_cursor; each "$COPILOT_LIST" step_copilot; each "$OPENCODE_LIST" step_opencode
# Cursor's official installer drops its own `agent` in ~/.local/bin and overwrites the bridge command: always use `cursor-agent`
[ -n "$CURSOR_LIST" ] && ! cursor_agent_clash && ui_warn "the 'agent' on your PATH is Cursor's, not the bridge's. Workers call cursor-agent; reinstall the bridge command with ./install.sh (without --no-path) or ln -sfn ~/.claude-bridge/bin/agent ~/.local/bin/agent"
[ -n "$CURSOR_LIST" ] && ui_info "Cursor: the bridge only ever calls 'cursor-agent', never 'agent'. Sign in with: cursor-agent login"
[ -n "$COPILOT_LIST" ] && ui_info "GitHub Copilot CLI: sign in once (copilot, then /login); each order spends premium requests of your monthly quota"
[ -n "$OPENCODE_LIST" ] && ui_info "OpenCode: all opencode-N workers share your opencode credentials; only *-free / *:free models are accepted unless BRIDGE_OPENCODE_PAID=1. Set a model with: agent model opencode-N <provider/model>"
NACC=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "$CLAUDE_LIST" "$CODEX_LIST" "$KIRO_LIST" "$AGY_LIST" "$CURSOR_LIST" "$COPILOT_LIST" "$OPENCODE_LIST" | sed '/^$/d' | wc -l | tr -d ' ')
[ "$NACC" -gt 0 ] || ui_warn "No accounts found. Use --claude-dir DIR / --codex-dir DIR."
if [ $DRY = 1 ]; then say; say "dry-run finished: nothing was written."; exit 0; fi
lines=("${GRN}${S_OK}${RST} $NACC account(s) configured")
[ "${UI_FAILS:-0}" -gt 0 ] && lines=("${RED}${S_FAIL}${RST} ${UI_FAILS} step(s) failed - see $UI_LOG")
[ -n "$SEL_SKILLS" ] && lines+=("${GRN}${S_OK}${RST} skills: $SEL_SKILLS")
for d in $CLAUDE_LIST $CODEX_LIST $KIRO_LIST $AGY_LIST $CURSOR_LIST $COPILOT_LIST $OPENCODE_LIST; do case "$UPTODATE" in *"|$d"*) st="already up to date";; *) st="updated";; esac
  lines+=("  ${DIM}$(get_name "$d")  $(tilde "$d")  ${RST}${GRN}$st${RST}"); done
lines+=("" "${BOLD}Next steps${RST}" "  1. Restart open Claude/Codex sessions")
[ "$PKG_AB" = 1 ] && ab_next_steps
ui_box "Done" "${lines[@]}"
exit 0
