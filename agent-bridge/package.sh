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
  MS_S=("how sessions learn the commands" "delivers messages between sessions" "no permission prompts for orders" "~/.local/bin"); MS_ON=(1 1 1 1); MS_F=(0 0 0 0)
  ui_h "agent-bridge options"; hint "↑↓ move · space select · enter continue"; echo
  ms_run; OPT_SKILL="${MS_ON[0]}"; OPT_HOOKS="${MS_ON[1]}"; OPT_BYPASS="${MS_ON[2]}"; OPT_PATH="${MS_ON[3]}"
}

do_scripts() {
  mkdir -p "$BR/bin" "$BR/inbox" "$BR/read" && chmod 700 "$BR"
  for s in "$SRC"/scripts/*; do chmod +x "$s"; ln -sfn "$s" "$BR/bin/$(basename "$s")"; done
  printf '%s\n' "$MAP" | sed '/^$/d' > "$conf"; printf 'BYPASS=%s\n' "$OPT_BYPASS" > "$BR/config"; }
do_path() { mkdir -p "$HOME/.local/bin" && ln -sfn "$BR/bin/agent" "$HOME/.local/bin/agent" && ln -sfn "$BR/bin/admin" "$HOME/.local/bin/admin"; }

# Per-account install / uninstall.
in_claude_ab() { local d="$1" n; n="$(get_name "$d")"; say "Claude  $n  ($d)"
  [ $DRY = 1 ] && { say "  [dry-run] env BRIDGE_NAME, hooks, commands, skill"; return 0; }
  mkdir -p "$d/commands" "$d/skills/agent-bridge" "$BR/inbox/$n"
  [ -f "$d/settings.json" ] || echo '{}' > "$d/settings.json"
  jq --arg n "$n" '.env = ((.env // {}) + {BRIDGE_NAME:$n}) | del(.env.BRIDGE_COMMANDERS)' "$d/settings.json" > "$d/s.tmp" && mv "$d/s.tmp" "$d/settings.json"
  [ $OPT_HOOKS = 1 ] && add_hooks "$d/settings.json" "$HOOK"
  if [ $OPT_SKILL = 1 ]; then cp "$SRC"/commands/*.md "$d/commands/"; cp "$SRC/SKILL.md" "$d/skills/agent-bridge/SKILL.md"; fi
  return 0; }
in_codex_ab() { local d="$1" n f; n="$(get_name "$d")"; say "Codex   $n  ($d)"
  [ $DRY = 1 ] && { say "  [dry-run] hooks.json, skill, prompts, AGENTS.md"; return 0; }
  mkdir -p "$d/skills/agent-bridge" "$d/prompts" "$BR/inbox/$n"
  if [ $OPT_SKILL = 1 ]; then
    for f in "$SRC"/commands/*.md; do sed '/^allowed-tools:/d' "$f" > "$d/prompts/$(basename "$f")"; done
    cp "$SRC/SKILL.md" "$d/skills/agent-bridge/SKILL.md"; fi
  [ $OPT_HOOKS = 1 ] && add_hooks "$d/hooks.json" "BRIDGE_NAME=$n $HOOK"
  touch "$d/AGENTS.md"; strip_block "$d/AGENTS.md"; agents_block "$n" >> "$d/AGENTS.md"; }
ab_install_claude() { in_claude_ab "$1"; }
ab_install_codex() { in_codex_ab "$1"; }
ab_un_claude() { local d="$1"; [ $DRY = 1 ] && return 0
  del_hooks "$d/settings.json"; [ -f "$d/settings.json" ] && { jq 'del(.env.BRIDGE_NAME,.env.BRIDGE_COMMANDERS)' "$d/settings.json" > "$d/s.tmp" && mv "$d/s.tmp" "$d/settings.json"; }
  rm -rf "$d/skills/agent-bridge" "$d/commands/admin.md" "$d/commands/agent.md"; return 0; }
ab_un_codex() { local d="$1"; [ $DRY = 1 ] && return 0
  del_hooks "$d/hooks.json"; rm -rf "$d/skills/agent-bridge" "$d/prompts/admin.md" "$d/prompts/agent.md"; strip_block "$d/AGENTS.md"; return 0; }
ab_next_steps() { # appends to the global "lines" array
  lines+=("  2. Codex: approve the hook with ${CYN}/hooks${RST}" "  3. Try ${CYN}/admin${RST}  then  ${CYN}/agent ping <name>${RST}")
  [ $OPT_PATH = 1 ] && case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) lines+=("" "${YEL}!${RST} add ~/.local/bin to your PATH to use 'agent' and 'admin'");; esac
  [ "$OS" = wsl ] && lines+=("" "${YEL}!${RST} WSL: Windows-side accounts need install.ps1 as well"); return 0; }
