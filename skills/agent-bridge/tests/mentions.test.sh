#!/usr/bin/env bash
# Mention subagents: one marked file per worker, user's own agent files untouched, stale ones removed, uninstall cleans up.
set -e
P="$(cd "$(dirname "$0")/.." && pwd)/package.sh"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
sed -n '/^MENTION_MARK=/,/^in_claude_ab() {/p' "$P" | sed '$d' > "$T/fn.sh"; . "$T/fn.sh"
DRY=0; d="$T/acct"; mkdir -p "$d/agents"
fail=0; ok() { echo "  ok   $1"; }; bad() { echo "  FAIL $1"; fail=1; }
MAP="/h/.claude=claude-1
/h/.claude-b=claude-2
/h/.codex=codex-1"
printf 'my own agent\n' > "$d/agents/claude-2.md"
mentions_sync "$d" claude-1
[ -f "$d/agents/codex-1.md" ] && ok "codex-1 mention created" || bad "codex-1 missing"
[ ! -f "$d/agents/claude-1.md" ] && ok "no mention of the session's own agent" || bad "own agent mentioned"
[ "$(cat "$d/agents/claude-2.md")" = "my own agent" ] && ok "user's own claude-2.md never overwritten" || bad "user file overwritten"
head -2 "$d/agents/codex-1.md" | grep -q '^name: codex-1$' && ok "front matter name" || bad "front matter"
grep -q 'agent codex-1 "<the task>"' "$d/agents/codex-1.md" && ok "forwards with agent codex-1" || bad "command line"
rm -f "$d/agents/claude-2.md"; MAP="/h/.claude=claude-1
/h/.claude-b=claude-2"
mentions_sync "$d" claude-1
[ -f "$d/agents/claude-2.md" ] && ok "claude-2 mention created once free" || bad "claude-2 missing"
[ ! -f "$d/agents/codex-1.md" ] && ok "stale mention removed" || bad "stale kept"
mentions_remove "$d"; [ -z "$(ls "$d/agents")" ] && ok "uninstall removes only marked files" || bad "leftovers"
exit $fail
