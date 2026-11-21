#!/usr/bin/env bash
# Tests for the agent-bridge runner with a fake `claude` (no API calls): replies, limit pause, API errors,
# alerts, stalls and worktrees. Usage: tests/run.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; OLDPATH="$PATH"
T="$(mktemp -d)"; trap 'kill $RP 2>/dev/null; rm -rf "$T"' EXIT; RP=""
S="$T/scripts"; mkdir -p "$S" "$T/bin" "$T/b/inbox/w2" "$T/home/.codex-fake" "$T/b/inbox/w1" "$T/b/inbox/kiro-1" "$T/b/inbox/adm" "$T/b/runs" "$T/home/.claude-fake" "$T/home/.kiro-fake" "$T/proj"
cp -a "$ROOT/agent-bridge/scripts/." "$S/"
export BRIDGE_DIR="$T/b" FAKEMODE="$T/mode" KIRO_TEST_HOME="$T/home/.kiro-fake" CLAUDE_TEST_ARGS="$T/claude-test-args" PATH="$T/bin:$PATH" BRIDGE_ALERT=0 BRIDGE_STALL=0 BRIDGE_WORKTREE=0 BRIDGE_LIMIT_PAUSE=3 BRIDGE_COMPACT_AT=40 BRIDGE_NOTIFY=0
printf "%s\n%s\n%s\n" "$T/home/.claude-fake=w1" "$T/home/.codex-fake=w2" "$T/home/.kiro-fake=kiro-1" > "$T/b/names.conf"; echo adm > "$T/b/admin"
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

echo; echo "passed: $pass  failed: $fail"; [ $fail = 0 ]
