#!/usr/bin/env bash
# Tests for the agent-bridge runner with a fake `claude` (no API calls): replies, limit pause, API errors,
# alerts, stalls and worktrees. Usage: tests/run.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; S="$ROOT/agent-bridge/scripts"; OLDPATH="$PATH"
T="$(mktemp -d)"; trap 'kill $RP 2>/dev/null; rm -rf "$T"' EXIT; RP=""
mkdir -p "$T/bin" "$T/b/inbox/w2" "$T/home/.codex-fake" "$T/b/inbox/w1" "$T/b/inbox/adm" "$T/b/runs" "$T/home/.claude-fake" "$T/proj"
export BRIDGE_DIR="$T/b" FAKEMODE="$T/mode" PATH="$T/bin:$PATH" BRIDGE_ALERT=0 BRIDGE_STALL=0 BRIDGE_WORKTREE=0 BRIDGE_LIMIT_PAUSE=3 BRIDGE_NOTIFY=0
printf "%s\n%s\n" "$T/home/.claude-fake=w1" "$T/home/.codex-fake=w2" > "$T/b/names.conf"; echo adm > "$T/b/admin"
cat > "$T/bin/claude" <<'EOF'
#!/bin/bash
echo "$PWD" > "$FAKEMODE.cwd"
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
out=""; while [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done
echo "$PWD" > "$FAKEMODE.cwd"; ev() { printf '%s\n' "$1"; }
ev '{"type":"thread.started","thread_id":"t-123"}'
case "$(cat "$FAKEMODE")" in
  limit) ev '{"type":"turn.failed","error":{"message":"You have hit your usage limit"}}'; exit 1;;
  *)     ev '{"type":"item.completed","item":{"id":"i0","type":"command_execution","command":"ls -la"}}'; sleep ${CODEXSLEEP:-0}; [ -n "$out" ] && echo "codex done" > "$out"; ev '{"type":"turn.completed"}';;
esac
EOF
chmod +x "$T/bin/claude" "$T/bin/codex"
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
check "worker ran inside its worktree" "$(cat "$T/mode.cwd")" "$T/proj/.worktrees/w1"
check "branch mejora/w1 exists" "$(git -C "$T/proj" branch --list 'mejora/w1' | tr -d ' *+')" "mejora/w1"
check ".worktrees is ignored" "$(git -C "$T/proj" status --short | wc -l | tr -d ' ')" "0"; stop

echo "codex worker"; rm -f "$T/b/inbox/adm"/*; echo ok > "$T/mode"; export CODEXSLEEP=9; start w2
printf 'From: adm\nTo: w2\nDate: x\nCwd: /tmp\n\nbuild it\n' > "$T/b/inbox/w2/$(date +%s%N)-de-adm.msg"; sleep 7
check "codex activity shown" "$("$S/agent" status 2>/dev/null | grep w2)" "~now: command_execution ls -la"; wait_reply 1
check "codex reply from -o file" "$(last_msg)" "codex done"; echo limit > "$T/mode"; printf 'From: adm\nTo: w2\nDate: x\nCwd: /tmp\n\nagain\n' > "$T/b/inbox/w2/$(date +%s%N)-de-adm.msg"; wait_reply 2
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
check "uninstall removes the Codex approvals" "$(grep -c trusted_hash "$H/.codex-b/config.toml" 2>/dev/null | tr -d '\n')" "0"

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
BRIDGE_NAME=adm "$S/agent" model w1 default >/dev/null
check "default removes it" "$([ -f "$T/b/models/w1" ] && echo present || echo gone)" "gone"
check "dashboard --once prints plain text" "$("$S/agent" dashboard --once | grep -c $'\033')" "0"
check "dashboard --once lists every agent" "$("$S/agent" dashboard --once | grep -c '^w[12] ')" "2"

echo; echo "passed: $pass  failed: $fail"; [ $fail = 0 ]
