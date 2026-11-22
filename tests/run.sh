#!/usr/bin/env bash
# Tests for the agent-bridge runner with a fake `claude` (no API calls): replies, limit pause, API errors,
# alerts, stalls and worktrees. Usage: tests/run.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; OLDPATH="$PATH"
export BRIDGE_OPENCODE_AUTO=0
T="$(mktemp -d)"; trap 'kill $RP 2>/dev/null; rm -rf "$T"' EXIT; RP=""
S="$T/scripts"; mkdir -p "$S" "$T/bin" "$T/b/inbox/w2" "$T/home/.codex-fake" "$T/b/inbox/w1" "$T/b/inbox/kiro-1" "$T/b/inbox/agy-1" "$T/b/inbox/cursor-1" "$T/b/inbox/copilot-1" "$T/b/inbox/opencode-1" "$T/b/inbox/opencode-2" "$T/home/cursorhome/.cursor" "$T/home/copilothome/.copilot" "$T/home/.opencode-1" "$T/home/.opencode-2" "$T/b/inbox/adm" "$T/b/runs" "$T/home/.claude-fake" "$T/home/.kiro-fake" "$T/home/agyhome/.gemini/antigravity-cli" "$T/proj"
cp -a "$ROOT/agent-bridge/scripts/." "$S/"
export BRIDGE_DIR="$T/b" FAKEMODE="$T/mode" KIRO_TEST_HOME="$T/home/.kiro-fake" CLAUDE_TEST_ARGS="$T/claude-test-args" PATH="$T/bin:$PATH" BRIDGE_ALERT=0 BRIDGE_STALL=0 BRIDGE_WORKTREE=0 BRIDGE_LIMIT_PAUSE=3 BRIDGE_COMPACT_AT=40 BRIDGE_NOTIFY=0
printf "%s\n%s\n%s\n%s\n" "$T/home/.claude-fake=w1" "$T/home/.codex-fake=w2" "$T/home/.kiro-fake=kiro-1" "$T/home/agyhome/.gemini/antigravity-cli=agy-1" > "$T/b/names.conf"; printf "%s\n%s\n" "$T/home/cursorhome/.cursor=cursor-1" "$T/home/copilothome/.copilot=copilot-1" >> "$T/b/names.conf"; printf "%s\n%s\n" "$T/home/.opencode-1=opencode-1" "$T/home/.opencode-2=opencode-2" >> "$T/b/names.conf"; echo adm > "$T/b/admin"
cat > "$T/bin/claude" <<'EOF'
#!/bin/bash
echo "$PWD" > "$FAKEMODE.cwd"
printf '%s\npct=%s\n' "$*" "${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-unset}" > "$CLAUDE_TEST_ARGS"
ev() { printf '%s\n' "$1"; }
case "$(cat "$FAKEMODE")" in
  ok)    ev '{"type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}'; ev '{"type":"result","subtype":"success","is_error":false,"result":"all done"}';;
  limit) ev '{"type":"rate_limit_event","rate_limit_info":{"status":"rejected","resetsAt":'"$(( $(date +%s) + 7 ))"'}}'; ev '{"type":"result","subtype":"success","is_error":true,"result":"You have hit your limit"}'; exit 1;;
  api)   echo "API Error: 529 overloaded" >&2; exit 1;;
  slow)  ev '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"make build"}}]}}'; sleep 8; ev '{"type":"result","is_error":false,"result":"slow done"}';;
esac
EOF
cat > "$T/bin/codex" <<'EOF'
#!/bin/bash
if [[ "$*" == 'debug models --bundled' ]]; then echo '{"models":[{"slug":"gpt-test","visibility":"list","priority":1,"context_window":50000}]}' ; exit 0; fi
echo "$*" > "$FAKEMODE.args"
out=""; while [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done
echo "$PWD" > "$FAKEMODE.cwd"; ev() { printf '%s\n' "$1"; }
ev '{"type":"thread.started","thread_id":"t-123"}'
case "$(cat "$FAKEMODE")" in
  limit) ev '{"type":"turn.failed","error":{"message":"You have hit your usage limit"}}'; exit 1;;
  *)     ev '{"type":"item.completed","item":{"id":"i0","type":"command_execution","command":"ls -la"}}'; sleep ${CODEXSLEEP:-0}; [ -n "$out" ] && echo "codex done" > "$out"; ev '{"type":"turn.completed"}';;
esac
EOF
cat > "$T/bin/kiro-cli" <<'EOF'
#!/bin/bash
if [[ "$*" != *"--list-models"* && "$*" != *"--list-sessions"* ]]; then echo "$*" > "$FAKEMODE.args"; fi
if [[ "$*" == *"--list-models"* ]]; then echo '{"models":[{"model_id":"auto"},{"model_id":"claude-sonnet-4.5"}]}'; exit 0; fi
if [[ "$*" == *"--list-sessions"* ]]; then printf '[{"cwd":"%s","sessions":[{"sessionId":"sess-kiro-test","updatedAt":"2026-11-21T20:00:00Z"}]}]\n' "$PWD"; exit 0; fi
if [[ "$*" == settings\ * ]]; then echo "$*" >> "$KIRO_TEST_HOME/settings.log"; mkdir -p "$PWD/.kiro/settings"; echo '{}' > "$PWD/.kiro/settings/cli.json"; exit 0; fi
[[ "$*" == *"--resume-id sess-kiro-test"* ]] && echo resumed >> "$KIRO_TEST_HOME/resumed.log"
echo '{"type":"sessionUpdate","data":{"sessionId":"sess-kiro-test","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Primera parte.\n"}}}}'
echo '{"type":"sessionUpdate","data":{"sessionId":"sess-kiro-test","update":{"sessionUpdate":"tool_call","toolCall":{"name":"fs_read","title":"Read file"}}}}'
echo '{"type":"sessionUpdate","data":{"sessionId":"sess-kiro-test","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"..."}}}}'
echo '{"type":"sessionUpdate","data":{"sessionId":"sess-kiro-test","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Segunda parte."}}}}'
echo '{"type":"runFinished","data":{"sessionId":"sess-kiro-test","status":"success","finalText":"Primera parte.\\nSegunda parte."}}'
EOF
cat > "$T/bin/agy" <<'EOF'
#!/bin/bash
if [ "$1" = models ]; then printf 'Fetching available models...\ngemini-3.8-flash-high\tGemini 3.8 Flash (High)\nclaude-sonnet-4-6\tClaude Sonnet 4.6 (Thinking)\n'; exit 0; fi
echo "$*" > "$FAKEMODE.agyargs"; echo "$HOME" > "$FAKEMODE.agyhome"; echo "$PWD" > "$FAKEMODE.agycwd"
[[ "$*" == *"--conversation conv-agy-test"* ]] && echo resumed >> "$FAKEMODE.agyresumed"
case "$(cat "$FAKEMODE")" in
  limit) echo "error: RESOURCE_EXHAUSTED: quota exceeded for this model" >&2; exit 1;;
  auth)  echo "authentication required" >&2; exit 1;;
esac
echo '{"event":"init","conversation_id":"conv-agy-test","init":{"cwd":"x","tools":[]}}'
echo '{"event":"step_update","step_update":{"conversation_id":"conv-agy-test","step_index":2,"state":"ACTIVE","step_type":"tool","tool_name":"run_command","tool_info":{"name":"run_command","parameters":{"CommandLine":"ls /tmp"}}}}'
echo '{"event":"step_update","step_update":{"conversation_id":"conv-agy-test","step_index":3,"state":"DONE","step_type":"agent_response","usage":{"input_tokens":100000,"cache_read_tokens":0,"output_tokens":0,"total_tokens":100000}}}'
echo '{"event":"result","result":{"conversation_id":"conv-agy-test","status":"SUCCESS","response":"agy listo\n","usage":{"total_tokens":1}}}'
EOF
chmod +x "$T/bin/agy"
chmod +x "$T/bin/claude" "$T/bin/codex"
chmod +x "$T/bin/kiro-cli"
chmod +x "$S/bridge-kiro-response"
pass=0; fail=0
check() { if [ "$2" = "$3" ] || { [ "${3:0:1}" = "~" ] && [[ "$2" == *"${3:1}"* ]]; }; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1: got [$2] expected [$3]"; fi; }
send() { printf 'From: adm\nTo: w1\nDate: x\nCwd: %s\n\n%s\n' "${2:-/tmp}" "$1" > "$T/b/inbox/w1/$(date +%s%N)-de-adm.msg"; }
last_msg() { local f; f="$(ls -t "$T/b/inbox/adm"/*.msg 2>/dev/null | head -1)"; [ -n "$f" ] && tail -n +6 "$f"; }
wait_reply() { local n="$1" i=0; while [ "$(ls "$T/b/inbox/adm" 2>/dev/null | wc -l)" -lt "$n" ] && [ $i -lt 60 ]; do sleep 0.5; i=$((i+1)); done; }
start() { local n="${1:-w1}"; "$S/bridge-runner" "$n" >/dev/null 2>&1 & RP=$!; echo $RP > "$T/b/runs/$n.pid"; sleep 1.5; }
stop() { kill $RP 2>/dev/null; wait $RP 2>/dev/null; RP=""; }
status() { "$S/agent" status 2>/dev/null; }

echo "ok reply"; echo ok > "$T/mode"; start; send "do it"; wait_reply 1
check "reply is the result event" "$(last_msg)" "all done"; check "status idle/ok" "$(status)" "~last order: ok"
check "Claude enables native auto-compact with settings" "$(grep -Fc -- '--settings {"autoCompactEnabled":true}' "$CLAUDE_TEST_ARGS")" "1"
check "Claude receives COMPACT_AT as a percent" "$(grep -c '^pct=40$' "$CLAUDE_TEST_ARGS")" "1"

echo "limit pauses the worker"; echo limit > "$T/mode"; send "again"; wait_reply 2
check "reply starts with LIMIT" "$(last_msg | cut -c1-6)" "LIMIT:"; sleep 1
check "status LIMITED" "$(status)" "~LIMITED"; echo ok > "$T/mode"; send "after pause"; sleep 1
check "paused: order waits in the inbox" "$(ls "$T/b/inbox/w1" | wc -l | tr -d ' ')" "1"; wait_reply 3
check "order runs after the reset" "$(last_msg)" "all done"

echo "api error"; echo api > "$T/mode"; send "x"; wait_reply 4
check "reply starts with API ERROR" "$(last_msg | cut -c1-10)" "API ERROR:"; stop

echo "alerts and activity"; echo slow > "$T/mode"; export BRIDGE_ALERT=3; start; send "long job"; sleep 5
check "status shows the order and the tool" "$(status)" "~now: Bash make build"; wait_reply 6
wait_reply 6; n=$(for f in "$T/b/inbox/adm"/*.msg; do tail -n +6 "$f"; done | grep -c '^ALERT:'); check "ALERT messages sent (>=1)" "$([ "$n" -ge 1 ] && echo yes)" "yes"; stop; export BRIDGE_ALERT=0

echo "stall"; rm -f "$T/b/inbox/adm"/*; export BRIDGE_STALL=3; start; send "hang"; sleep 7
check "STALLED message sent" "$(for f in "$T/b/inbox/adm"/*.msg; do tail -n +6 "$f"; done | grep -c '^STALLED:')" "1"; stop; export BRIDGE_STALL=0

echo "worktree"; ( cd "$T/proj" && git init -q . && git -c user.email=a@b -c user.name=t commit -q --allow-empty -m i ); rm -f "$T/b/inbox/adm"/*
export BRIDGE_WORKTREE=1; echo ok > "$T/mode"; start; send "in repo" "$T/proj"; wait_reply 1
worktree_physical="$(cd "$T/proj/.worktrees/w1" && pwd -P)"; got_physical="$(cd "$(cat "$T/mode.cwd")" && pwd -P)"
check "worker ran inside its worktree" "$got_physical" "$worktree_physical"
check "branch mejora/w1 exists" "$(git -C "$T/proj" branch --list 'mejora/w1' | tr -d ' *+')" "mejora/w1"
check ".worktrees is ignored" "$(git -C "$T/proj" status --short | wc -l | tr -d ' ')" "0"; stop

echo "codex worker"; rm -f "$T/b/inbox/adm"/*; echo ok > "$T/mode"; export CODEXSLEEP=9; start w2
printf 'From: adm\nTo: w2\nDate: x\nCwd: /tmp\n\nbuild it\n' > "$T/b/inbox/w2/$(date +%s%N)-de-adm.msg"; sleep 7
check "codex activity shown" "$("$S/agent" status 2>/dev/null | grep w2)" "~now: command_execution ls -la"; wait_reply 1
check "codex reply from -o file" "$(last_msg)" "codex done"
check "Codex native threshold is 40% of the model window" "$(grep -c 'model_auto_compact_token_limit=20000' "$FAKEMODE.args")" "1"
echo limit > "$T/mode"; printf 'From: adm\nTo: w2\nDate: x\nCwd: /tmp\n\nagain\n' > "$T/b/inbox/w2/$(date +%s%N)-de-adm.msg"; wait_reply 2
check "codex limit classified" "$(last_msg | cut -c1-6)" "LIMIT:"; stop; unset CODEXSLEEP

echo "reassign on limit"; rm -f "$T/b/inbox/adm"/* "$T/b/runs"/*; echo ok > "$T/mode"; export BRIDGE_REASSIGN=1
start w2; R2=$RP; start w1; echo limit > "$T/mode.w1"
# w1 hits the limit; w2 (idle) must receive the order
cat > "$T/bin/claude" <<'EOF'
#!/bin/bash
echo "$PWD" > "$FAKEMODE.cwd"
printf '%s\n' '{"type":"rate_limit_event","rate_limit_info":{"status":"rejected","resetsAt":'"$(( $(date +%s) + 30 ))"'}}' '{"type":"result","is_error":true,"result":"You have hit your limit"}'; exit 1
EOF
send "urgent order"; wait_reply 2; sleep 1
check "limit reply mentions the reassignment" "$(for f in "$T/b/inbox/adm"/*.msg; do tail -n +6 "$f"; done | grep -c "reassigned to 'w2'")" "1"
check "w2 replied to the admin" "$(for f in "$T/b/inbox/adm"/*.msg; do tail -n +6 "$f"; done | grep -c 'codex done')" "1"
stop; kill $R2 2>/dev/null; unset BRIDGE_REASSIGN

echo "agent wt"; ( cd "$T/proj" && git worktree remove --force .worktrees/w1 2>/dev/null; git branch -D mejora/w1 -q 2>/dev/null; git worktree add -q .worktrees/w1 -b mejora/w1 && cd .worktrees/w1 && echo x > f && git add f && git -c user.email=a@b -c user.name=t commit -qm feat )
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=a@b GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=a@b
check "wt list shows the commit" "$(cd "$T/proj" && "$S/agent" wt list)" "~1 commit(s) ahead"
check "merge without --yes only previews" "$(cd "$T/proj" && "$S/agent" wt merge w1 | tail -1)" "(add --yes to merge)"
( cd "$T/proj" && "$S/agent" wt merge w1 --yes >/dev/null 2>&1 ); check "merge --yes brings the commit" "$(git -C "$T/proj" log --oneline | grep -c feat)" "1"
( cd "$T/proj" && "$S/agent" wt clean w1 --yes >/dev/null 2>&1 ); check "clean removes the worktree" "$([ -d "$T/proj/.worktrees/w1" ] && echo present || echo gone)" "gone"

echo "installer: install, --check, --fix, uninstall"; export PATH="$OLDPATH"
H="$T/ihome"; mkdir -p "$H/.claude-a" "$H/.codex-b"; echo '{}' > "$H/.claude-a/settings.json"; echo '{}' > "$H/.codex-b/hooks.json"; cp ~/.codex/auth.json "$H/.codex-b/" 2>/dev/null
inst() { ( cd "$ROOT" && HOME="$H" BRIDGE_DIR= ./install.sh "$@" ); }
inst --yes --no-path --claude-dir "$H/.claude-a" --codex-dir "$H/.codex-b" >/dev/null 2>&1
chk() { inst --check --claude-dir "$H/.claude-a" --codex-dir "$H/.codex-b" 2>&1; }
check "check passes right after install" "$(chk >/dev/null; echo $?)" "$(command -v codex >/dev/null && echo 0 || echo 0)"
rm -rf "$H/.claude-a/skills/agent-bridge"
check "check detects a missing skill" "$(chk | grep -c 'skill missing')" "1"
inst --check --fix --claude-dir "$H/.claude-a" --codex-dir "$H/.codex-b" >/dev/null 2>&1
check "--fix restores it" "$([ -f "$H/.claude-a/skills/agent-bridge/SKILL.md" ] && echo yes)" "yes"
inst --uninstall --claude-dir "$H/.claude-a" --codex-dir "$H/.codex-b" >/dev/null 2>&1
check "uninstall removes the Codex approvals" "$(if [ -f "$H/.codex-b/config.toml" ]; then grep -c trusted_hash "$H/.codex-b/config.toml" 2>/dev/null || echo 0; else echo 0; fi | tail -1)" "0"

echo "dashboard data (bridge-usage) and statusline wrapper"; export PATH="$OLDPATH"
mkdir -p "$T/home/.codex-fake/sessions/2026/01/01"; NOW=$(date +%s)
{ echo '{"type":"turn_context","payload":{"model":"gpt-test","cwd":"'"$T"'/proj"}}'
  echo '{"type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":1000,"last_token_usage":{"total_tokens":260}},"rate_limits":{"primary":{"used_percent":47.5,"window_minutes":300,"resets_at":'$((NOW+999))'},"secondary":{"used_percent":90.2,"window_minutes":10080,"resets_at":'$((NOW+9999))'}}}}'; } > "$T/home/.codex-fake/sessions/2026/01/01/rollout.jsonl"
U="$("$S/bridge-usage" w2)"
check "codex model"   "$(echo "$U" | cut -f1)" "gpt-test"
check "codex project" "$(echo "$U" | cut -f2)" "proj"
check "codex branch"  "$(echo "$U" | cut -f3)" "$(git -C "$T/proj" rev-parse --abbrev-ref HEAD)"
check "codex ctx 26%" "$(echo "$U" | cut -f4)" "26"
check "codex 5h 47%"  "$(echo "$U" | cut -f5)" "47"
check "codex week 90%" "$(echo "$U" | cut -f6)" "90"
H2="$T/ihome2"; mkdir -p "$H2/.claude-a"; echo '{"statusLine":{"type":"command","command":"echo ORIG-BAR"}}' > "$H2/.claude-a/settings.json"
( cd "$ROOT" && HOME="$H2" BRIDGE_DIR= ./install.sh --yes --no-path --no-trust --claude-dir "$H2/.claude-a" >/dev/null 2>&1 )
OUT="$(printf '{"model":{"display_name":"Sonnet"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":30},"rate_limits":{"five_hour":{"used_percentage":50},"seven_day":{"used_percentage":70}}}' "$T/proj" | BRIDGE_DIR="$H2/.claude-bridge" BRIDGE_NAME="$(awk -F= '{print $2}' "$H2/.claude-bridge/names.conf" | head -1)" "$H2/.claude-bridge/bin/bridge-statusline")"
check "wrapper keeps the original bar" "$OUT" "ORIG-BAR"
UN="$(awk -F= '{print $2}' "$H2/.claude-bridge/names.conf" | head -1)"
printf '{"model":{"display_name":"Sonnet"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":30},"rate_limits":{"five_hour":{"used_percentage":50},"seven_day":{"used_percentage":70}}}' "$T/proj" | BRIDGE_DIR="$H2/.claude-bridge" BRIDGE_NAME="$UN" "$H2/.claude-bridge/bin/bridge-statusline" >/dev/null
check "claude usage from the saved JSON" "$(BRIDGE_DIR="$H2/.claude-bridge" "$H2/.claude-bridge/bin/bridge-usage" "$UN" | cut -f1,4,5,6 | tr '\t' ' ')" "Sonnet 30 50 70"
# status line cache of another setup (matched by the transcript path of the account)
mkdir -p "$T/sc"; printf '{"transcript_path":"%s/projects/x/s.jsonl","model":{"display_name":"Opus"},"cwd":"%s","context_window":{"used_percentage":12},"rate_limits":{"five_hour":{"used_percentage":33},"seven_day":{"used_percentage":44}}}' "$H2/.claude-a" "$T/proj" > "$T/sc/s1.json"
rm -f "$H2/.claude-bridge/usage"/*.json
check "claude usage from a status line cache" "$(BRIDGE_STATUS_CACHE="$T/sc" BRIDGE_DIR="$H2/.claude-bridge" "$H2/.claude-bridge/bin/bridge-usage" "$UN" | cut -f1,4,5,6 | tr '\t' ' ')" "Opus 12 33 44"
( cd "$ROOT" && HOME="$H2" BRIDGE_DIR= ./install.sh --uninstall --claude-dir "$H2/.claude-a" >/dev/null 2>&1 )
check "uninstall restores the original status line" "$(jq -r '.statusLine.command' "$H2/.claude-a/settings.json")" "echo ORIG-BAR"

echo "Claude context cache survives empty live logs"
cat > "$T/b/logs/w1.live" <<'EOF'
{"type":"assistant","message":{"usage":{"input_tokens":80000,"cache_read_input_tokens":20000}}}
{"type":"result","modelUsage":{"sonnet":{"contextWindow":200000}}}
EOF
check "Claude context is cached when known" "$("$S/bridge-usage" w1 | cut -f4)" "50"
: > "$T/b/logs/w1.live"
check "Claude context is retained when the live log empties" "$("$S/bridge-usage" w1 | cut -f4)" "50"
old_ctx_at=$(( $(date +%s) - 1200 )); jq --argjson at "$old_ctx_at" '.updated_at=$at' "$T/b/usage/w1.last" > "$T/ctx-cache-old.tmp" && mv "$T/ctx-cache-old.tmp" "$T/b/usage/w1.last"
check "Claude cache exposes its original sample age" "$([ "$("$S/bridge-usage" w1 | cut -f7)" -ge 1199 ] && echo yes)" "yes"
cp "$ROOT/agent-bridge/widget/test/fixtures/claude-live-no-result.jsonl" "$T/b/logs/w1.live"
check "Claude computes context from live assistant usage before result" "$("$S/bridge-usage" w1 | cut -f4)" "32"
check "Claude caches context window by model" "$(jq -r 'select(.window==1000000 and .model=="claude-sonnet-5-5")|"ok"' "$T/b/usage/w1.window")" "ok"
printf '%s\n' '{"type":"system","subtype":"init","model":"claude-sonnet-5-5","cwd":"/tmp/project"}' > "$T/b/logs/w1.live"
check "Claude retains last percent when current live log has no assistant or result" "$("$S/bridge-usage" w1 | cut -f4)" "32"

echo "model switch and dashboard command"
export PATH="$T/bin:$OLDPATH"; echo adm > "$T/b/admin"
check "non-admin cannot change a model" "$(BRIDGE_NAME=w1 "$S/agent" model w2 gpt-x 2>&1 | head -1 | cut -c1-30)" "only the admin can change a wo"
check "admin sets a model" "$(BRIDGE_NAME=adm "$S/agent" model w1 claude-opus-test | head -1)" "w1: model set to claude-opus-test (applies from its next order)"
check "bad model names are refused" "$(BRIDGE_NAME=adm "$S/agent" model w1 'a b;rm' 2>&1 | head -1)" "invalid model name"
cat > "$T/bin/claude" <<'EOF'
#!/bin/bash
echo "$*" > "$FAKEMODE.args"; printf '%s\n' '{"type":"result","is_error":false,"result":"fine"}'
EOF
rm -f "$T/b/inbox/adm"/*; start; send "use the model"; wait_reply 1; stop
check "worker runs with --model" "$(grep -o -- '--model [^ ]*' "$T/mode.args")" "--model claude-opus-test"
check "effort validated per provider (claude has no 'minimal')" "$(BRIDGE_NAME=adm "$S/agent" effort w1 minimal 2>&1 | head -1)" "invalid effort for claude: use one of low medium high xhigh max, or default"
check "model + effort in one command" "$(BRIDGE_NAME=adm "$S/agent" model w1 claude-opus-test high | tail -1)" "w1: effort set to high (applies from its next order)"
rm -f "$T/b/inbox/adm"/*; start; send "use the effort"; wait_reply 1; stop
check "claude worker runs with --effort" "$(grep -o -- '--effort [^ ]*' "$T/mode.args")" "--effort high"
cat > "$T/bin/codex" <<'EOF'
#!/bin/bash
echo "$*" > "$FAKEMODE.args"; out=""; while [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done; [ -n "$out" ] && echo done > "$out"; echo '{"type":"turn.completed"}'
EOF
BRIDGE_NAME=adm "$S/agent" effort w2 xhigh >/dev/null; rm -f "$T/b/inbox/adm"/*; start w2
printf 'From: adm\nTo: w2\nDate: x\nCwd: /tmp\n\nhi\n' > "$T/b/inbox/w2/$(date +%s%N)-de-adm.msg"; wait_reply 1; stop
check "codex worker gets the reasoning effort" "$(grep -c 'model_reasoning_effort="xhigh"' "$T/mode.args")" "1"
BRIDGE_NAME=adm "$S/agent" effort w2 default >/dev/null
BRIDGE_NAME=adm "$S/agent" model w1 default >/dev/null; BRIDGE_NAME=adm "$S/agent" effort w1 default >/dev/null
check "default removes it" "$([ -f "$T/b/models/w1" ] && echo present || echo gone)" "gone"
check "dashboard --once prints plain text" "$("$S/agent" dashboard --once | grep -c $'\033')" "0"
check "dashboard --once lists every agent" "$("$S/agent" dashboard --once | grep -c '^w[12] ')" "2"

echo "Kiro provider via copied scripts and an isolated bridge directory"
check "Kiro response helper joins anonymized multipart fixture" "$("$S/bridge-kiro-response" "$ROOT/agent-bridge/widget/test/fixtures/kiro-multipart-anonymized.jsonl")" "1. Primera observación completa.
2. Segunda observación.
3. Tercera observación."
check "provider resolver detects Kiro config prefix" "$("$S/bridge-provider" kiro-1)" "kiro"
check "Kiro tier defaults to normal without account quota data" "$("$S/bridge-capacity" --tier kiro-1)" "normal"
check "Kiro model is checked against CLI model list" "$(BRIDGE_NAME=adm "$S/agent" model kiro-1 claude-sonnet-4.5)" "kiro-1: model set to claude-sonnet-4.5 (applies from its next order)"
BRIDGE_NAME=adm "$S/agent" effort kiro-1 high >/dev/null
mkdir -p "$T/kiro-proj"
base_count="$(ls "$T/b/inbox/adm" 2>/dev/null | wc -l | tr -d ' ')"; start kiro-1
printf 'From: adm\nTo: kiro-1\nDate: x\nCwd: %s\n\nresponde solo: ok\n' "$T/kiro-proj" > "$T/b/inbox/kiro-1/$(date +%s%N)-de-adm.msg"; wait_reply $((base_count + 1));
check "Kiro runner returns every multipart text fragment" "$(last_msg)" "Primera parte.
Segunda parte."
check "Kiro prompt forbids sending its own bridge reply" "$(grep -c "Do not use the 'agent' or 'admin' command" "$FAKEMODE.args")" "1"
kiro_session_file="$(find "$T/b/sessions/kiro-1" -maxdepth 1 -type f ! -name '*.cwd' | head -1)"
check "Kiro saves list-sessions id for next order" "$(cat "$kiro_session_file" 2>/dev/null)" "sess-kiro-test"
printf 'From: adm\nTo: kiro-1\nDate: x\nCwd: %s\n\nsecond order\n' "$T/kiro-proj" > "$T/b/inbox/kiro-1/$(date +%s%N)-de-adm.msg"; wait_reply $((base_count + 2)); stop
check "Kiro resumes by its saved session id" "$(cat "$T/home/.kiro-fake/resumed.log" 2>/dev/null | wc -l | tr -d ' ')" "1"
check "Kiro receives configured model and effort" "$(grep -c -- '--model claude-sonnet-4.5 --effort high' "$FAKEMODE.args" 2>/dev/null || true)" "1"
check "Kiro gets COMPACT_AT as a temporary workspace setting" "$(grep -c 'compaction.autoCompactionThreshold 40 --workspace' "$KIRO_TEST_HOME/settings.log")" "2"
check "Kiro workspace override is removed after each order" "$([ -e "$T/kiro-proj/.kiro/settings/cli.json" ] && echo present || echo absent)" "absent"

echo "Kiro usage cache parses monthly plan and deletes usage-only sessions"
UCLI="$T/bin/kiro-usage-cli"; UB="$T/kiro-usage-bridge"; mkdir -p "$UB"
cat > "$UCLI" <<'EOF'
#!/bin/bash
if [[ "$*" == *"--list-sessions"* ]]; then
  n=$(cat "$KIRO_USAGE_TEST.list-count" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$KIRO_USAGE_TEST.list-count"
  if [ "$n" -eq 1 ]; then echo '[]'; else echo '[{"sessions":[{"sessionId":"usage-only-session"}]}]'; fi
elif [[ "$*" == *"--delete-session"* ]]; then echo "${@: -1}" > "$KIRO_USAGE_TEST.deleted"
elif [[ "$*" == *"/usage"* ]]; then
  echo 'Estimated Usage | resets on 2026-12-01 | KIRO FREE'
  echo 'Credits (7.25 of 50 covered in plan), 14.5%'
  echo usage >> "$KIRO_USAGE_TEST.usage-count"
fi
EOF
chmod +x "$UCLI"; export KIRO_USAGE_TEST="$T/kiro-usage-test"
BRIDGE_KIRO_CLI="$UCLI" "$S/bridge-kiro-usage" sample "$UB" >/dev/null
for i in $(seq 1 40); do [ -s "$UB/sample.kiro.json" ] && break; sleep 0.1; done
check "Kiro monthly percent is parsed" "$(jq -r .percent "$UB/sample.kiro.json" 2>/dev/null)" "14.5"
check "Kiro credit totals and plan are cached" "$(jq -r '[.credits_used,.credits_total,.plan]|@tsv' "$UB/sample.kiro.json" 2>/dev/null)" "7.25	50	KIRO FREE"
check "Kiro usage-only session was deleted" "$(cat "$KIRO_USAGE_TEST.deleted" 2>/dev/null)" "usage-only-session"
BRIDGE_KIRO_CLI="$UCLI" "$S/bridge-kiro-usage" sample "$UB" >/dev/null
check "Kiro /usage runs once within its five-minute cache" "$(wc -l < "$KIRO_USAGE_TEST.usage-count" | tr -d ' ')" "1"
mkdir -p "$T/home/.kiro-fake/sessions/hash/sess-kiro-test"
printf '{"modelId":"auto","contextSnapshotModelDisplay":{"display":"Auto (model selected dynamically on the server)"},"workspacePaths":["%s"]}\n' "$T/proj" > "$T/home/.kiro-fake/sessions/hash/sess-kiro-test/session.json"
printf '%s\n' '{"payload":{"type":"session_metadata","key":"contextUsage","value":{"usagePercentage":33}}}' > "$T/home/.kiro-fake/sessions/hash/sess-kiro-test/messages.jsonl"
cp "$UB/sample.kiro.json" "$T/b/usage/kiro-1.kiro.json"
BRIDGE_NAME=adm "$S/agent" model kiro-1 default >/dev/null
KUSAGE="$("$S/bridge-usage" kiro-1)"
check "Kiro quota is exposed as monthly dashboard fields" "$(printf '%s' "$KUSAGE" | cut -f11,15,16,17)" "14.5	7.25	50	KIRO FREE"
check "Kiro capacity tiers use its monthly quota" "$("$S/bridge-capacity" --tier kiro-1)" "heavy"
KJSON="$(BRIDGE_NAME=adm "$S/agent" dashboard --json)"
check "Kiro auto model explains task routing" "$(printf '%s' "$KJSON" | jq -r '.agents[]|select(.name=="kiro-1")|.model_note')" "Kiro elige el modelo según la tarea (Models chosen by task)."
check "Kiro widget data carries plan, credits and monthly percent" "$(printf '%s' "$KJSON" | jq -r '.agents[]|select(.name=="kiro-1")|[.monthly.used,.monthly.credits_used,.monthly.credits_total,.monthly.plan]|@tsv')" "14.5	7.25	50	KIRO FREE"

echo "Antigravity (agy) provider with a fake agy"
mkdir -p "$T/agy-proj"
check "provider resolver detects Antigravity config dir" "$("$S/bridge-provider" agy-1)" "antigravity"
check "agy HOME is derived from the account dir" "$("$S/bridge-agy-home" "$T/home/agyhome/.gemini/antigravity-cli")" "$T/home/agyhome"
check "provider marker overrides the folder name" "$(mkdir -p "$T/home/custom" && echo antigravity > "$T/home/custom/provider" && "$S/bridge-provider" "$T/home/custom")" "antigravity"
check "Antigravity tier defaults to normal without quota data" "$("$S/bridge-capacity" --tier agy-1)" "normal"
check "Antigravity model is checked against agy models" "$(BRIDGE_NAME=adm "$S/agent" model agy-1 gemini-3.8-flash-high high)" "agy-1: model set to gemini-3.8-flash-high (applies from its next order)
agy-1: effort set to high (applies from its next order)"
check "Antigravity rejects an unknown model" "$(BRIDGE_NAME=adm "$S/agent" model agy-1 nope 2>&1)" "unknown Antigravity model or agy not available (see: agy models)"
check "Antigravity accepts max effort" "$(BRIDGE_NAME=adm "$S/agent" effort agy-1 max)" "agy-1: effort set to max (applies from its next order)"
BRIDGE_NAME=adm "$S/agent" effort agy-1 high >/dev/null
echo ok > "$T/mode"; base_count="$(ls "$T/b/inbox/adm" 2>/dev/null | wc -l | tr -d ' ')"; start agy-1
printf 'From: adm\nTo: agy-1\nDate: x\nCwd: %s\n\nresponde solo: ok\n' "$T/agy-proj" > "$T/b/inbox/agy-1/$(date +%s%N)-de-adm.msg"; wait_reply $((base_count + 1))
check "Antigravity runner returns the final response" "$(last_msg)" "agy listo"
check "Antigravity runs with bypass, model and effort" "$(grep -c -e '--dangerously-skip-permissions' -e '--model gemini-3.8-flash-high --effort high' "$FAKEMODE.agyargs")" "1"
check "Antigravity runs under its own HOME" "$(cat "$FAKEMODE.agyhome")" "$T/home/agyhome"
check "Antigravity prompt forbids sending its own bridge reply" "$(grep -c "Do not use the 'agent' or 'admin' command" "$FAKEMODE.agyargs")" "1"
agy_sf="$(find "$T/b/sessions/agy-1" -maxdepth 1 -type f ! -name '*.cwd' | head -1)"
check "Antigravity saves its conversation id" "$(cat "$agy_sf" 2>/dev/null)" "conv-agy-test"
printf 'From: adm\nTo: agy-1\nDate: x\nCwd: %s\n\nsecond order\n' "$T/agy-proj" > "$T/b/inbox/agy-1/$(date +%s%N)-de-adm.msg"; wait_reply $((base_count + 2))
check "Antigravity resumes by --conversation" "$(wc -l < "$FAKEMODE.agyresumed" 2>/dev/null | tr -d ' ')" "1"
check "Antigravity context is estimated from tokens" "$("$S/bridge-usage" agy-1 | cut -f4)" "10"
check "Antigravity usage shows set model and effort" "$("$S/bridge-usage" agy-1 | cut -f1,8)" "gemini-3.8-flash-high	high"
AJSON="$(BRIDGE_NAME=adm "$S/agent" dashboard --json)"
check "Antigravity dashboard row has kind, no quota windows" "$(printf '%s' "$AJSON" | jq -r '.agents[]|select(.name=="agy-1")|[.kind,.five_hour.used,.weekly.used,.monthly.used,.tier]|@tsv')" "antigravity				normal"
check "Antigravity feed reads its live log" "$(BRIDGE_DIR="$T/b" node "$S/bridge-feed" agy-1 --json 2>/dev/null | jq -r "[.events[]|select(.role==\"tool\")|.tool]|first" 2>/dev/null)" "run_command"
echo limit > "$T/mode"; printf 'From: adm\nTo: agy-1\nDate: x\nCwd: %s\n\nthird\n' "$T/agy-proj" > "$T/b/inbox/agy-1/$(date +%s%N)-de-adm.msg"; wait_reply $((base_count + 3)); stop
check "Antigravity quota error pauses the worker as LIMIT" "$(last_msg | head -c 6)" "LIMIT:"
check "Antigravity pause is recorded" "$(sed -n 's/^last_kind=//p' "$T/b/runs/agy-1.state")" "limit"
echo auth > "$T/mode"; sleep 3.5; printf 'From: adm\nTo: agy-1\nDate: x\nCwd: %s\n\nfourth\n' "$T/agy-proj" > "$T/b/inbox/agy-1/$(date +%s%N)-de-adm.msg"; start agy-1; wait_reply $((base_count + 4)); stop
check "Antigravity authentication failure is an API error" "$(last_msg | head -c 10)" "API ERROR:"

echo "Cursor (cursor-agent), GitHub Copilot and OpenCode providers with fakes"; export PATH="$T/bin:$OLDPATH"
mkdir -p "$T/cur-proj" "$T/cop-proj" "$T/oc-proj" "$T/oc-proj2"
cat > "$T/bin/cursor-agent" <<'EOF'
#!/bin/bash
if [ "$1" = models ]; then printf 'Available models\n\nauto - Auto (current, default)\ncomposer-2.5 - Composer 2.5\n'; exit 0; fi
echo "$*" > "$FAKEMODE.curargs"; echo "$HOME" > "$FAKEMODE.curhome"
[[ "$*" == *"--resume sess-cur-test"* ]] && echo resumed >> "$FAKEMODE.curresumed"
case "$(cat "$FAKEMODE")" in
  limit) echo "ActionRequiredError: You've hit your usage limit Get Cursor Pro for more Agent usage" >&2; exit 1;;
  auth)  echo "Error: Not logged in. Run cursor-agent login" >&2; exit 1;;
esac
echo '{"type":"system","subtype":"init","session_id":"sess-cur-test","model":"Auto"}'
echo '{"type":"tool_call","subtype":"started","call_id":"c1","tool_call":{"shellToolCall":{"args":{"command":"ls /tmp"}}},"session_id":"sess-cur-test"}'
echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"cursor listo"}]},"session_id":"sess-cur-test"}'
echo '{"type":"result","subtype":"success","is_error":false,"result":"cursor listo","session_id":"sess-cur-test","usage":{"inputTokens":40000,"outputTokens":10,"cacheReadTokens":10000,"cacheWriteTokens":0}}'
EOF
cat > "$T/bin/copilot" <<'EOF'
#!/bin/bash
echo "$*" > "$FAKEMODE.copargs"; echo "$HOME" > "$FAKEMODE.copcwd"; pwd > "$FAKEMODE.copcwd"
[[ "$*" == *"--resume sess-cop-test"* ]] && echo resumed >> "$FAKEMODE.copresumed"
case "$(cat "$FAKEMODE")" in
  limit) echo "Error: 429 rate limit exceeded for premium requests" >&2; exit 1;;
  auth)  echo "Access denied by policy settings" >&2; exit 1;;
esac
echo '{"type":"session.start","data":{"sessionId":"sess-cop-test"}}'
echo '{"type":"tool.execution_start","data":{"toolName":"bash","arguments":{"command":"ls /tmp"}}}'
echo '{"type":"assistant.message","data":{"content":"copilot listo"}}'
echo '{"type":"result","sessionId":"sess-cop-test","exitCode":0,"usage":{"premiumRequests":1}}'
EOF
cat > "$T/bin/opencode" <<'EOF'
#!/bin/bash
if [ "$1" = models ]; then printf 'opencode/test-free\nopencode/paid-model\nanthropic/claude-haiku-5-5\nopenrouter/x/y:free\n'; exit 0; fi
echo "$*" > "$FAKEMODE.ocargs"; pwd > "$FAKEMODE.occwd"
[[ "$*" == *" -s ses_test"* ]] && echo resumed >> "$FAKEMODE.ocresumed"
case "$(cat "$FAKEMODE")" in
  limit) echo '{"type":"error","sessionID":"ses_test","error":{"name":"APIError","data":{"message":"Rate limit exceeded: free-models-per-day"}}}'; exit 0;;
  tpm)   echo '{"type":"error","sessionID":"ses_test","error":{"data":{"message":"Request too large for model: tokens per minute (TPM): Limit 8000"}}}'; exit 0;;
  scope) echo '{"type":"error","sessionID":"ses_test","error":{"data":{"message":"This API key is not scoped to a workspace"}}}'; exit 0;;
esac
echo '{"type":"step_start","sessionID":"ses_test","part":{"type":"step-start"}}'
echo '{"type":"tool_use","sessionID":"ses_test","part":{"type":"tool","tool":"bash","state":{"status":"completed","input":{"command":"ls /tmp"},"output":"x"}}}'
echo '{"type":"text","sessionID":"ses_test","part":{"type":"text","text":"opencode listo"}}'
echo '{"type":"step_finish","sessionID":"ses_test","part":{"type":"step-finish","tokens":{"total":32000,"input":31000,"output":10},"cost":0.0025}}'
EOF
chmod +x "$T/bin/cursor-agent" "$T/bin/copilot" "$T/bin/opencode"
check "provider resolver detects Cursor, Copilot and OpenCode marker dirs" "$("$S/bridge-provider" cursor-1)/$("$S/bridge-provider" copilot-1)/$("$S/bridge-provider" opencode-2)" "cursor/copilot/opencode"
check "account HOME of .cursor is its parent" "$("$S/bridge-account-home" "$T/home/cursorhome/.cursor")" "$T/home/cursorhome"
check "Cursor model is checked against cursor-agent models" "$(BRIDGE_NAME=adm "$S/agent" model cursor-1 composer-2.5)" "cursor-1: model set to composer-2.5 (applies from its next order)"
check "Cursor rejects an unknown model" "$(BRIDGE_NAME=adm "$S/agent" model cursor-1 nope 2>&1)" "unknown Cursor model or cursor-agent not available (see: cursor-agent models)"
check "Cursor has no configurable effort" "$(BRIDGE_NAME=adm "$S/agent" effort cursor-1 high 2>&1 | head -c 34)" "effort is not configurable for cur"
check "OpenCode has no configurable effort" "$(BRIDGE_NAME=adm "$S/agent" effort opencode-1 high 2>&1 | head -c 34)" "effort is not configurable for ope"
check "OpenCode accepts a free model" "$(BRIDGE_NAME=adm "$S/agent" model opencode-1 opencode/test-free)" "opencode-1: model set to opencode/test-free (applies from its next order)"
check "OpenCode accepts an openrouter :free model" "$(BRIDGE_NAME=adm "$S/agent" model opencode-2 openrouter/x/y:free | head -c 24)" "opencode-2: model set to"
check "OpenCode rejects a paid Zen model" "$(BRIDGE_NAME=adm "$S/agent" model opencode-1 opencode/paid-model 2>&1 | grep -c 'opencode/paid-model is not a free model')" "1"
check "OpenCode rejects a paid anthropic/* model" "$(BRIDGE_NAME=adm "$S/agent" model opencode-1 anthropic/claude-haiku-5-5 2>&1 | grep -c 'anthropic/claude-haiku-5-5 is not a free model')" "1"
check "BRIDGE_OPENCODE_PAID=1 allows a paid model" "$(BRIDGE_OPENCODE_PAID=1 BRIDGE_NAME=adm "$S/agent" model opencode-1 anthropic/claude-haiku-5-5 | head -c 22)" "opencode-1: model set "
BRIDGE_NAME=adm "$S/agent" model opencode-1 opencode/test-free >/dev/null
check "Copilot accepts effort low..xhigh" "$(BRIDGE_NAME=adm "$S/agent" effort copilot-1 high)" "copilot-1: effort set to high (applies from its next order)"
BRIDGE_NAME=adm "$S/agent" effort copilot-1 default >/dev/null
check "Cursor/OpenCode tier defaults to normal, Copilot is light" "$("$S/bridge-capacity" --tier cursor-1)/$("$S/bridge-capacity" --tier opencode-1)/$("$S/bridge-capacity" --tier copilot-1)" "normal/normal/light"
echo ok > "$T/mode"; base_count="$(ls "$T/b/inbox/adm" 2>/dev/null | wc -l | tr -d ' ')"; start cursor-1
printf 'From: adm\nTo: cursor-1\nDate: x\nCwd: %s\n\nresponde solo: ok\n' "$T/cur-proj" > "$T/b/inbox/cursor-1/$(date +%s%N)-de-adm.msg"; wait_reply $((base_count + 1))
check "Cursor runner returns the final result" "$(last_msg)" "cursor listo"
check "Cursor runs cursor-agent -p with force, trust and model" "$(tr '\n' ' ' < "$FAKEMODE.curargs" | grep -c -e '^-p .*--output-format stream-json --force --trust --model composer-2.5')" "1"
check "Cursor runs under its account HOME" "$(cat "$FAKEMODE.curhome")" "$T/home/cursorhome"
check "Cursor prompt forbids sending its own bridge reply" "$(grep -c "Do not use the 'agent' or 'admin' command" "$FAKEMODE.curargs")" "1"
cur_sf="$(find "$T/b/sessions/cursor-1" -maxdepth 1 -type f ! -name '*.cwd' | head -1)"
check "Cursor saves its session id" "$(cat "$cur_sf" 2>/dev/null)" "sess-cur-test"
printf 'From: adm\nTo: cursor-1\nDate: x\nCwd: %s\n\nsecond\n' "$T/cur-proj" > "$T/b/inbox/cursor-1/$(date +%s%N)-de-adm.msg"; wait_reply $((base_count + 2))
check "Cursor resumes with --resume <id>" "$(wc -l < "$FAKEMODE.curresumed" 2>/dev/null | tr -d ' ')" "1"
check "Cursor context is estimated from input+cache tokens" "$("$S/bridge-usage" cursor-1 | cut -f4)" "25"
check "Cursor usage shows the chosen model" "$("$S/bridge-usage" cursor-1 | cut -f1)" "composer-2.5"
CJSON="$(BRIDGE_NAME=adm "$S/agent" dashboard --json)"
check "Cursor dashboard row has kind and no quota windows" "$(printf '%s' "$CJSON" | jq -r '.agents[]|select(.name=="cursor-1")|[.kind,.five_hour.used,.weekly.used,.monthly.used,.tier]|@tsv')" "cursor				normal"
check "Cursor feed shows its tool call" "$(BRIDGE_DIR="$T/b" node "$S/bridge-feed" cursor-1 --json 2>/dev/null | jq -r '[.events[]|select(.role=="tool")|.tool]|first' 2>/dev/null)" "shell"
echo limit > "$T/mode"; printf 'From: adm\nTo: cursor-1\nDate: x\nCwd: %s\n\nthird\n' "$T/cur-proj" > "$T/b/inbox/cursor-1/$(date +%s%N)-de-adm.msg"; wait_reply $((base_count + 3)); stop
check "Cursor usage limit pauses the worker as LIMIT" "$(last_msg | head -c 6)" "LIMIT:"
check "Cursor pause is recorded" "$(sed -n 's/^last_kind=//p' "$T/b/runs/cursor-1.state")" "limit"
echo auth > "$T/mode"; sleep 3.5; printf 'From: adm\nTo: cursor-1\nDate: x\nCwd: %s\n\nfourth\n' "$T/cur-proj" > "$T/b/inbox/cursor-1/$(date +%s%N)-de-adm.msg"; start cursor-1; wait_reply $((base_count + 4)); stop
check "Cursor login failure is an API error" "$(last_msg | head -c 10)" "API ERROR:"
rm -f "$FAKEMODE.curargs"; echo ok > "$T/mode"; BRIDGE_BYPASS=safe start cursor-1; printf 'From: adm\nTo: cursor-1\nDate: x\nCwd: %s\n\nfifth\n' "$T/cur-proj" > "$T/b/inbox/cursor-1/$(date +%s%N)-de-adm.msg"; wait_reply $((base_count + 5)); stop
check "Cursor safe mode drops --force" "$(grep -c -e '--force' "$FAKEMODE.curargs")" "0"
echo ok > "$T/mode"; base_count="$(ls "$T/b/inbox/adm" 2>/dev/null | wc -l | tr -d ' ')"; start copilot-1
printf 'From: adm\nTo: copilot-1\nDate: x\nCwd: %s\n\nresponde solo: ok\n' "$T/cop-proj" > "$T/b/inbox/copilot-1/$(date +%s%N)-de-adm.msg"; wait_reply $((base_count + 1))
check "Copilot runner returns the final answer" "$(last_msg)" "copilot listo"
check "Copilot runs copilot -p with allow-all-tools, no-ask-user, json" "$(tr '\n' ' ' < "$FAKEMODE.copargs" | grep -c -e '^-p .*--no-ask-user --output-format json --allow-all-tools')" "1"
check "Copilot prompt forbids sending its own bridge reply" "$(grep -c "Do not use the 'agent' or 'admin' command" "$FAKEMODE.copargs")" "1"
cop_sf="$(find "$T/b/sessions/copilot-1" -maxdepth 1 -type f ! -name '*.cwd' | head -1)"
check "Copilot saves its sessionId" "$(cat "$cop_sf" 2>/dev/null)" "sess-cop-test"
printf 'From: adm\nTo: copilot-1\nDate: x\nCwd: %s\n\nsecond\n' "$T/cop-proj" > "$T/b/inbox/copilot-1/$(date +%s%N)-de-adm.msg"; wait_reply $((base_count + 2))
check "Copilot resumes with --resume <id>" "$(wc -l < "$FAKEMODE.copresumed" 2>/dev/null | tr -d ' ')" "1"
check "Copilot counts premium requests" "$("$S/bridge-usage" copilot-1 | cut -f13)" "2"
CPJSON="$(BRIDGE_NAME=adm "$S/agent" dashboard --json)"
check "Copilot dashboard row: kind, light tier, premium counter" "$(printf '%s' "$CPJSON" | jq -r '.agents[]|select(.name=="copilot-1")|[.kind,.tier,.credit_used]|@tsv')" "copilot	light	2"
check "Copilot feed shows its tool call" "$(BRIDGE_DIR="$T/b" node "$S/bridge-feed" copilot-1 --json 2>/dev/null | jq -r '[.events[]|select(.role=="tool")|.tool]|first' 2>/dev/null)" "bash"
echo limit > "$T/mode"; printf 'From: adm\nTo: copilot-1\nDate: x\nCwd: %s\n\nthird\n' "$T/cop-proj" > "$T/b/inbox/copilot-1/$(date +%s%N)-de-adm.msg"; wait_reply $((base_count + 3)); stop
check "Copilot rate limit pauses the worker as LIMIT" "$(last_msg | head -c 6)" "LIMIT:"
echo auth > "$T/mode"; sleep 3.5; printf 'From: adm\nTo: copilot-1\nDate: x\nCwd: %s\n\nfourth\n' "$T/cop-proj" > "$T/b/inbox/copilot-1/$(date +%s%N)-de-adm.msg"; start copilot-1; wait_reply $((base_count + 4)); stop
check "Copilot 'Access denied by policy' is an API error, not a limit" "$(last_msg | head -c 10)" "API ERROR:"
# --- OpenCode: two workers share one install, each with its own model/session
echo ok > "$T/mode"; base_count="$(ls "$T/b/inbox/adm" 2>/dev/null | wc -l | tr -d ' ')"; start opencode-1
printf 'From: adm\nTo: opencode-1\nDate: x\nCwd: %s\n\nresponde solo: ok\n' "$T/oc-proj" > "$T/b/inbox/opencode-1/$(date +%s%N)-de-adm.msg"; wait_reply $((base_count + 1))
check "OpenCode runner returns the final text" "$(last_msg)" "opencode listo"
check "OpenCode runs opencode run -m <free model> --format json --dir" "$(grep -c -e "^run -m opencode/test-free --format json --dir $T/oc-proj " "$FAKEMODE.ocargs")" "1"
check "OpenCode prompt forbids sending its own bridge reply" "$(grep -c "Do not use the 'agent' or 'admin' command" "$FAKEMODE.ocargs")" "1"
oc_sf="$(find "$T/b/sessions/opencode-1" -maxdepth 1 -type f ! -name '*.cwd' | head -1)"
check "OpenCode saves its sessionID" "$(cat "$oc_sf" 2>/dev/null)" "ses_test"
printf 'From: adm\nTo: opencode-1\nDate: x\nCwd: %s\n\nsecond\n' "$T/oc-proj" > "$T/b/inbox/opencode-1/$(date +%s%N)-de-adm.msg"; wait_reply $((base_count + 2))
check "OpenCode resumes with -s <id>" "$(wc -l < "$FAKEMODE.ocresumed" 2>/dev/null | tr -d ' ')" "1"
check "OpenCode context is estimated from step_finish tokens" "$("$S/bridge-usage" opencode-1 | cut -f4)" "25"
check "OpenCode accumulates cost across orders" "$("$S/bridge-usage" opencode-1 | cut -f13)" "0.005000"
OJSON="$(BRIDGE_NAME=adm "$S/agent" dashboard --json)"
check "OpenCode dashboard row shows model and cost" "$(printf '%s' "$OJSON" | jq -r '.agents[]|select(.name=="opencode-1")|[.kind,.model,.credit_used]|@tsv')" "opencode	opencode/test-free	0.005"
check "OpenCode feed shows its tool call" "$(BRIDGE_DIR="$T/b" node "$S/bridge-feed" opencode-1 --json 2>/dev/null | jq -r '[.events[]|select(.role=="tool")|.tool]|first' 2>/dev/null)" "bash"
echo limit > "$T/mode"; printf 'From: adm\nTo: opencode-1\nDate: x\nCwd: %s\n\nthird\n' "$T/oc-proj" > "$T/b/inbox/opencode-1/$(date +%s%N)-de-adm.msg"; wait_reply $((base_count + 3)); stop
check "OpenCode free-models-per-day is LIMIT" "$(last_msg | head -c 6)" "LIMIT:"
echo tpm > "$T/mode"; sleep 3.5; printf 'From: adm\nTo: opencode-1\nDate: x\nCwd: %s\n\nfourth\n' "$T/oc-proj" > "$T/b/inbox/opencode-1/$(date +%s%N)-de-adm.msg"; start opencode-1; wait_reply $((base_count + 4)); stop
check "OpenCode 'tokens per minute (TPM)' is LIMIT" "$(last_msg | head -c 6)" "LIMIT:"
echo scope > "$T/mode"; sleep 3.5; printf 'From: adm\nTo: opencode-1\nDate: x\nCwd: %s\n\nfifth\n' "$T/oc-proj" > "$T/b/inbox/opencode-1/$(date +%s%N)-de-adm.msg"; start opencode-1; wait_reply $((base_count + 5)); stop
check "'not scoped to a workspace' is API with the anthropic-workspace-id hint" "$(last_msg | head -c 10)/$(last_msg | grep -c 'anthropic-workspace-id')" "API ERROR:/1"
# a paid model set behind the runner's back is refused at run time
echo ok > "$T/mode"; printf '%s' "anthropic/claude-haiku-5-5" > "$T/b/models/opencode-2"; rm -f "$FAKEMODE.ocargs"; start opencode-2
printf 'From: adm\nTo: opencode-2\nDate: x\nCwd: %s\n\nsixth\n' "$T/oc-proj2" > "$T/b/inbox/opencode-2/$(date +%s%N)-de-adm.msg"; wait_reply $((base_count + 6)); stop
check "OpenCode runner refuses a paid model without BRIDGE_OPENCODE_PAID" "$(last_msg | head -c 9)/$([ -e "$FAKEMODE.ocargs" ] && echo ran || echo notrun)" "ERROR (co/notrun"
rm -f "$T/b/models/opencode-2"
# process saturation (EAGAIN) is retried
printf '#!/bin/bash\nn="$FAKEMODE.eagain"; c=$(cat "$n" 2>/dev/null || echo 0); echo $((c+1)) > "$n"\nif [ "$c" -lt 2 ]; then echo "Failed to start thread: EAGAIN" >&2; exit 134; fi\necho "{\\"type\\":\\"text\\",\\"sessionID\\":\\"ses_e\\",\\"part\\":{\\"text\\":\\"tras reintento\\"}}"\n' > "$T/bin/opencode.eagain"; chmod +x "$T/bin/opencode.eagain"
cp "$T/bin/opencode" "$T/bin/opencode.real"; cp "$T/bin/opencode.eagain" "$T/bin/opencode"; rm -f "$FAKEMODE.eagain"
BRIDGE_RETRY_WAIT=1 start opencode-1
printf 'From: adm\nTo: opencode-1\nDate: x\nCwd: %s\n\nseventh\n' "$T/oc-proj" > "$T/b/inbox/opencode-1/$(date +%s%N)-de-adm.msg"; wait_reply $((base_count + 7)); stop
check "EAGAIN/134 is retried and the order succeeds" "$(last_msg)/$(cat "$FAKEMODE.eagain")" "tras reintento/3"
cp "$T/bin/opencode.real" "$T/bin/opencode"; rm -f "$T/bin/opencode.real" "$T/bin/opencode.eagain"
echo "installer: Cursor, Copilot and OpenCode accounts"; export PATH="$OLDPATH"
HC="$T/ihome3"; mkdir -p "$HC/.cursor" "$HC/.copilot" "$HC/.opencode-1" "$HC/.opencode-2"
instc() { ( cd "$ROOT" && HOME="$HC" BRIDGE_DIR= ./install.sh "$@" ); }
check "installer --list shows Cursor, Copilot and both OpenCode workers" "$(instc --list --cursor-dir "$HC/.cursor" --copilot-dir "$HC/.copilot" --opencode-dir "$HC/.opencode-1" --opencode-dir "$HC/.opencode-2" 2>&1 | grep -c -e '^cursor ' -e '^copilot ' -e '^opencode ')" "4"
instc --yes --no-path --cursor-dir "$HC/.cursor" --copilot-dir "$HC/.copilot" --opencode-dir "$HC/.opencode-1" --opencode-dir "$HC/.opencode-2" >/dev/null 2>&1
check "installer writes Cursor skill and provider marker" "$([ -f "$HC/.cursor/skills/agent-bridge/SKILL.md" ] && cat "$HC/.cursor/provider")" "cursor"
check "installer writes the Copilot block and marker" "$(grep -c BRIDGE-BEGIN "$HC/.copilot/copilot-instructions.md")/$(cat "$HC/.copilot/provider")" "1/copilot"
check "installer writes both OpenCode markers and names them opencode-1/2" "$(cat "$HC/.opencode-1/provider" "$HC/.opencode-2/provider" | tr '\n' ' ')/$(grep -c 'opencode-[12]$' "$HC/.claude-bridge/names.conf")" "opencode opencode /2"
check "installer check passes for Cursor, Copilot and OpenCode" "$(instc --check --cursor-dir "$HC/.cursor" --copilot-dir "$HC/.copilot" --opencode-dir "$HC/.opencode-1" --opencode-dir "$HC/.opencode-2" >/dev/null 2>&1; echo $?)" "0"
check "--opencode-workers N creates N marker folders" "$(HOME="$T/ihome4" bash -c 'mkdir -p "$HOME"; cd "$0" && BRIDGE_DIR= ./install.sh --yes --no-path --opencode-workers 3 >/dev/null 2>&1; ls -d "$HOME"/.opencode-* | wc -l' "$ROOT")" "3"
# a Cursor-installed `agent` shadowing the bridge command is reported
mkdir -p "$HC/fakebin/cursor-agent"; printf '#!/bin/sh\necho 2026.11.22-test cursor\n' > "$HC/fakebin/cursor-agent/agent"; chmod +x "$HC/fakebin/cursor-agent/agent"; ln -sfn "$HC/fakebin/cursor-agent/agent" "$HC/fakebin/agent"
check "installer warns when 'agent' on PATH is Cursor's" "$(PATH="$HC/fakebin:$OLDPATH" instc --check --cursor-dir "$HC/.cursor" 2>&1 | grep -c "is Cursor's")" "1"
instc --uninstall --cursor-dir "$HC/.cursor" --copilot-dir "$HC/.copilot" --opencode-dir "$HC/.opencode-1" --opencode-dir "$HC/.opencode-2" >/dev/null 2>&1
check "uninstall removes Cursor, Copilot and OpenCode files" "$([ -e "$HC/.cursor/skills/agent-bridge" ] || [ -e "$HC/.copilot/skills/agent-bridge" ] || [ -e "$HC/.copilot/provider" ] || [ -e "$HC/.opencode-1/provider" ] || [ -e "$HC/.opencode-2/skills/agent-bridge" ] && echo left || echo clean)" "clean"

echo; echo "passed: $pass  failed: $fail"; [ $fail = 0 ]
