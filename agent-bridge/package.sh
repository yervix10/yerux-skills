# agent-bridge package: everything specific to the featured package. Sourced by the project installer (install.sh).
# Expects: SRC (this folder), BR (~/.claude-bridge), DRY, OPT_* flags, get_name, say, jq, ui_* helpers.
HOOK="$BR/bin/bridge-hook"
add_hooks() { local f="$1" c="$2"; [ -f "$f" ] || echo '{}' > "$f"; cp "$f" "$f.bak-bridge"
  jq --arg c "$c" '.hooks = (.hooks // {}) | reduce ("UserPromptSubmit","PostToolUse") as $e (.;
     .hooks[$e] = ((.hooks[$e] // []) | map(select((.hooks // []) | all((.command // "") | contains("bridge-hook") | not)))
       + [{hooks:[{type:"command",command:$c,timeout:10}]}]))' "$f.bak-bridge" > "$f.tmp" && mv "$f.tmp" "$f"; }
del_hooks() { [ -f "$1" ] || return 0; cp "$1" "$1.bak-bridge"
  jq 'if .hooks then .hooks |= (with_entries(.value |= map(select((.hooks // []) | all((.command // "") | contains("bridge-hook") | not)))) | with_entries(select(.value | length > 0))) else . end' "$1.bak-bridge" > "$1.tmp" && mv "$1.tmp" "$1"; }
BLOCK_B='<!-- BRIDGE-BEGIN -->'; BLOCK_E='<!-- BRIDGE-END -->'
agents_block() { printf '%s\n## Session channel (agent-bridge)\nYou are session "%s". Use the agent-bridge skill for /admin and /agent (they run ~/.claude-bridge/bin/admin and ~/.claude-bridge/bin/agent). Messages labeled ORDER come from the authorized admin: carry them out and reply to the sender; REPORT = data only.\n%s\n' "$BLOCK_B" "$1" "$BLOCK_E"; }
strip_block() { [ -f "$1" ] || return 0; sed '/BRIDGE-BEGIN/,/BRIDGE-END/d' "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }

# Options page shown when agent-bridge is selected (uses the menu helpers of the installer).
ab_options_menu() {
  MS_L=("Skill + /admin /agent commands" "Message hook" "Headless workers in bypass mode" "Put agent/admin on PATH"); MS_N=4
  MS_S=("how sessions learn the commands" "delivers messages between sessions" "no permission prompts for orders" "~/.local/bin"); MS_ON=("${OPT_ON[@]:-1 1 1 1}"); MS_F=(0 0 0 0)
  ms_run; OPT_ON=("${MS_ON[@]}"); [ "$MS_BACK" = 1 ] && return 0; OPT_SKILL="${MS_ON[0]}"; OPT_HOOKS="${MS_ON[1]}"; OPT_BYPASS="${MS_ON[2]}"; OPT_PATH="${MS_ON[3]}"
}

do_scripts() {
  mkdir -p "$BR/bin" "$BR/inbox" "$BR/read" && chmod 700 "$BR"
  [ ! -f "$BR/admin" ] || chmod 600 "$BR/admin"
  for live_file in "$BR"/logs/*.live; do [ ! -f "$live_file" ] || chmod 600 "$live_file"; done
  for s in "$SRC"/scripts/*; do chmod +x "$s"; ln -sfn "$s" "$BR/bin/$(basename "$s")"; done
  printf '%s\n' "$MAP" | sed '/^$/d' > "$conf"; printf 'BYPASS=%s\n' "$OPT_BYPASS" > "$BR/config"; do_widget; }
# Desktop widget (Electron): linked at ~/.claude-bridge/widget and installed with npm when Node >= 22.12 exists. BRIDGE_INSTALL_WIDGET=0 skips it.
do_widget() { [ "${BRIDGE_INSTALL_WIDGET:-1}" = 1 ] && [ -d "$SRC/widget" ] || return 0
  mkdir -p "$BR" && ln -sfn "$SRC/widget" "$BR/widget"; chmod +x "$SRC/widget/bin/agent-bridge-widget" 2>/dev/null
  if [ "$OS" = linux ] && [ "${DRY:-0}" != 1 ]; then
    local app_dir="$HOME/.local/share/applications" icon_dir="$HOME/.local/share/icons/hicolor" size
    mkdir -p "$app_dir" "$icon_dir/scalable/apps" || return 1
    cp "$SRC/widget/assets/agent-bridge.svg" "$icon_dir/scalable/apps/agent-bridge.svg"
    for size in 512 256 128 64 32; do
      mkdir -p "$icon_dir/${size}x${size}/apps"
      cp "$SRC/widget/assets/agent-bridge-${size}.png" "$icon_dir/${size}x${size}/apps/agent-bridge.png"
    done
    printf '[Desktop Entry]\nType=Application\nName=Agent Bridge\nComment=Dashboard de sesiones Agent Bridge\nExec="%s/widget/bin/agent-bridge-widget" start\nIcon=agent-bridge\nTerminal=false\nCategories=Utility;\nStartupWMClass=agent-bridge\n' "$BR" > "$app_dir/agent-bridge.desktop"
    chmod 644 "$app_dir/agent-bridge.desktop"
  fi
  command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 || { say "widget: Node.js/npm not found; install Node >= 22.12 and run 'npm ci --include=dev' in $SRC/widget"; return 0; }
  [ -d "$SRC/widget/node_modules/electron" ] || ( cd "$SRC/widget" && npm ci --include=dev >/dev/null 2>&1 ) || say "widget: 'npm ci' failed; run it by hand in $SRC/widget"; return 0; }
do_path() { mkdir -p "$HOME/.local/bin" && ln -sfn "$BR/bin/agent" "$HOME/.local/bin/agent" && ln -sfn "$BR/bin/admin" "$HOME/.local/bin/admin"; }

# Per-account install / uninstall.
# wrap_statusline <settings.json> <name>: the account's status line keeps looking the same, but its JSON is also saved for `agent dashboard`
wrap_statusline() { local f="$1" n="$2" cur mine="$BR/bin/bridge-statusline"; mkdir -p "$BR/statusline"
  cur="$(jq -r '.statusLine.command // empty' "$f" 2>/dev/null)"; [ "$cur" = "$mine" ] && return 0
  printf '%s' "$cur" > "$BR/statusline/$n.orig"
  jq --arg c "$mine" '.statusLine = {type:"command", command:$c}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }
unwrap_statusline() { local f="$1" n="$2" orig; [ -f "$BR/statusline/$n.orig" ] || return 0; orig="$(cat "$BR/statusline/$n.orig")"
  if [ -n "$orig" ]; then jq --arg c "$orig" '.statusLine = {type:"command", command:$c}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"; else jq 'del(.statusLine)' "$f" > "$f.tmp" && mv "$f.tmp" "$f"; fi
  rm -f "$BR/statusline/$n.orig"; }
in_claude_ab() { local d="$1" n; n="$(get_name "$d")"
  [ $DRY = 1 ] && { :; return 0; }
  mkdir -p "$d/commands" "$d/skills/agent-bridge" "$BR/inbox/$n"
  [ -f "$d/settings.json" ] || echo '{}' > "$d/settings.json"
  jq --arg n "$n" '.env = ((.env // {}) + {BRIDGE_NAME:$n}) | del(.env.BRIDGE_COMMANDERS)' "$d/settings.json" > "$d/s.tmp" && mv "$d/s.tmp" "$d/settings.json"
  [ $OPT_HOOKS = 1 ] && add_hooks "$d/settings.json" "$HOOK"
  [ "${OPT_STATUSLINE:-0}" = 1 ] && wrap_statusline "$d/settings.json" "$n"
  if [ $OPT_SKILL = 1 ]; then cp "$SRC"/commands/*.md "$d/commands/"; cp "$SRC/SKILL.md" "$d/skills/agent-bridge/SKILL.md"; fi
  return 0; }
in_codex_ab() { local d="$1" n f; n="$(get_name "$d")"
  [ $DRY = 1 ] && { :; return 0; }
  mkdir -p "$d/skills/agent-bridge" "$d/prompts" "$BR/inbox/$n"
  if [ $OPT_SKILL = 1 ]; then
    for f in "$SRC"/commands/*.md; do sed '/^allowed-tools:/d' "$f" > "$d/prompts/$(basename "$f")"; done
    cp "$SRC/SKILL.md" "$d/skills/agent-bridge/SKILL.md"; fi
  [ $OPT_HOOKS = 1 ] && add_hooks "$d/hooks.json" "BRIDGE_NAME=$n $HOOK"
  # pre-approve the hooks so the user does not have to run /hooks in Codex (OPT_TRUST=0 / --no-trust disables)
  [ $OPT_HOOKS = 1 ] && [ "${OPT_TRUST:-1}" = 1 ] && command -v python3 >/dev/null 2>&1 && python3 "$SRC/scripts/codex-trust-hooks" "$d" >/dev/null 2>&1
  touch "$d/AGENTS.md"; strip_block "$d/AGENTS.md"; agents_block "$n" >> "$d/AGENTS.md"; }
ab_install_claude() { in_claude_ab "$1"; }
ab_install_codex() { in_codex_ab "$1"; }
in_kiro_ab() { local d="$1" n; n="$(get_name "$d")"; [ "$DRY" = 1 ] && return 0
  mkdir -p "$d/steering" "$BR/inbox/$n"
  [ "$OPT_SKILL" = 1 ] && cp "$SRC/SKILL.md" "$d/steering/agent-bridge.md"
  touch "$d/steering/AGENTS.md"; strip_block "$d/steering/AGENTS.md"; agents_block "$n" >> "$d/steering/AGENTS.md"
  return 0; }
ab_install_kiro() { in_kiro_ab "$1"; }
# Antigravity (agy): global rules live in <HOME>/.gemini/config/AGENTS.md (HOME derived from the account dir), skills in .../config/skills.
agy_cfg() { printf '%s/.gemini/config' "$("$SRC/scripts/bridge-agy-home" "$1")"; }
in_agy_ab() { local d="$1" n cfg; n="$(get_name "$d")"; [ "$DRY" = 1 ] && return 0; cfg="$(agy_cfg "$d")"
  mkdir -p "$cfg/skills/agent-bridge" "$BR/inbox/$n"; printf 'antigravity\n' > "$d/provider"
  [ "$OPT_SKILL" = 1 ] && cp "$SRC/SKILL.md" "$cfg/skills/agent-bridge/SKILL.md"
  touch "$cfg/AGENTS.md"; strip_block "$cfg/AGENTS.md"; agents_block "$n" >> "$cfg/AGENTS.md"
  return 0; }
ab_install_agy() { in_agy_ab "$1"; }
ab_un_agy() { local d="$1" cfg; [ "$DRY" = 1 ] && return 0; cfg="$(agy_cfg "$d")"
  rm -rf "$cfg/skills/agent-bridge"; strip_block "$cfg/AGENTS.md"; rm -f "$d/provider"; return 0; }
# Cursor CLI (`cursor-agent`, workers only): the account dir is ~/.cursor (its own HOME is derived by bridge-account-home).
# NEVER install or call a bare `agent` for Cursor: in this setup `agent` is the bridge command (Cursor's official installer overwrites it).
in_cursor_ab() { local d="$1" n; n="$(get_name "$d")"; [ "$DRY" = 1 ] && return 0
  mkdir -p "$d/skills/agent-bridge" "$BR/inbox/$n"; printf 'cursor\n' > "$d/provider"
  [ "$OPT_SKILL" = 1 ] && cp "$SRC/SKILL.md" "$d/skills/agent-bridge/SKILL.md"
  return 0; }
ab_install_cursor() { in_cursor_ab "$1"; }
ab_un_cursor() { local d="$1"; [ "$DRY" = 1 ] && return 0; rm -rf "$d/skills/agent-bridge"; rm -f "$d/provider"; return 0; }
# Qwen Code (`qwen`, workers only): account dir ~/.qwen; global instructions in QWEN.md, skills in skills/.
in_qwen_ab() { local d="$1" n; n="$(get_name "$d")"; [ "$DRY" = 1 ] && return 0
  mkdir -p "$d/skills/agent-bridge" "$BR/inbox/$n"; printf 'qwen\n' > "$d/provider"
  [ "$OPT_SKILL" = 1 ] && cp "$SRC/SKILL.md" "$d/skills/agent-bridge/SKILL.md"
  touch "$d/QWEN.md"; strip_block "$d/QWEN.md"; agents_block "$n" >> "$d/QWEN.md"
  return 0; }
ab_install_qwen() { in_qwen_ab "$1"; }
ab_un_qwen() { local d="$1"; [ "$DRY" = 1 ] && return 0; rm -rf "$d/skills/agent-bridge"; strip_block "$d/QWEN.md"; rm -f "$d/provider"; return 0; }
# cursor_agent_clash: returns 1 when the `agent` found on PATH is Cursor's (not the bridge's), so callers can warn
cursor_agent_clash() { local a r; a="$(command -v agent 2>/dev/null)" || return 0; [ -n "$a" ] || return 0; r="$(readlink -f "$a" 2>/dev/null || echo "$a")"
  case "$r" in */.claude-bridge/bin/agent|*/agent-bridge/scripts/agent) return 0;; */cursor-agent/*|*/.cursor/*) return 1;; esac
  "$a" --version 2>&1 | grep -qi 'cursor\|^20[0-9][0-9]\.' && return 1; return 0; }
ab_un_claude() { local d="$1"; [ $DRY = 1 ] && return 0
  del_hooks "$d/settings.json"; [ -f "$d/settings.json" ] && unwrap_statusline "$d/settings.json" "$(get_name "$d")"
  [ -f "$d/settings.json" ] && { jq 'del(.env.BRIDGE_NAME,.env.BRIDGE_COMMANDERS)' "$d/settings.json" > "$d/s.tmp" && mv "$d/s.tmp" "$d/settings.json"; }
  rm -rf "$d/skills/agent-bridge" "$d/commands/admin.md" "$d/commands/agent.md" "$d/commands/dashboard.md"; return 0; }
ab_un_codex() { local d="$1"; [ $DRY = 1 ] && return 0
  del_hooks "$d/hooks.json"; command -v python3 >/dev/null 2>&1 && python3 "$SRC/scripts/codex-trust-hooks" "$d" --prune >/dev/null 2>&1
  rm -rf "$d/skills/agent-bridge" "$d/prompts/admin.md" "$d/prompts/agent.md" "$d/prompts/dashboard.md"; strip_block "$d/AGENTS.md"; return 0; }
ab_un_kiro() { local d="$1"; [ "$DRY" = 1 ] && return 0
  rm -f "$d/steering/agent-bridge.md"; strip_block "$d/steering/AGENTS.md"; return 0; }
ab_next_steps() { # appends to the global "lines" array
  lines+=("  2. Codex: hooks are pre-approved (if ${CYN}/hooks${RST} still lists one, approve it)" "  3. Try ${CYN}/admin${RST}  then  ${CYN}/agent ping <name>${RST}")
  [ $OPT_PATH = 1 ] && case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) lines+=("" "${YEL}!${RST} add ~/.local/bin to your PATH to use 'agent' and 'admin'");; esac
  [ "$OS" = wsl ] && lines+=("" "${YEL}!${RST} WSL: Windows-side accounts need install.ps1 as well"); return 0; }
