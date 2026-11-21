#!/usr/bin/env bash
# Tests for the agent-bridge runner with a fake `claude` (no API calls): replies, limit pause, API errors,
# alerts, stalls and worktrees. Usage: tests/run.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; S="$ROOT/agent-bridge/scripts"
T="$(mktemp -d)"; trap 'kill $RP 2>/dev/null; rm -rf "$T"' EXIT; RP=""
mkdir -p "$T/bin" "$T/b/inbox/w1" "$T/b/inbox/adm" "$T/b/runs" "$T/home/.claude-fake" "$T/proj"
export BRIDGE_DIR="$T/b" FAKEMODE="$T/mode" PATH="$T/bin:$PATH" BRIDGE_ALERT=0 BRIDGE_STALL=0 BRIDGE_WORKTREE=0 BRIDGE_LIMIT_PAUSE=3
echo "$T/home/.claude-fake=w1" > "$T/b/names.conf"; echo adm > "$T/b/admin"
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
chmod +x "$T/bin/claude"
pass=0; fail=0
check() { if [ "$2" = "$3" ] || { [ "${3:0:1}" = "~" ] && [[ "$2" == *"${3:1}"* ]]; }; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1: got [$2] expected [$3]"; fi; }
send() { printf 'From: adm\nTo: w1\nDate: x\nCwd: %s\n\n%s\n' "${2:-/tmp}" "$1" > "$T/b/inbox/w1/$(date +%s%N)-de-adm.msg"; }
last_msg() { local f; f="$(ls -t "$T/b/inbox/adm"/*.msg 2>/dev/null | head -1)"; [ -n "$f" ] && tail -n +6 "$f"; }
wait_reply() { local n="$1" i=0; while [ "$(ls "$T/b/inbox/adm" 2>/dev/null | wc -l)" -lt "$n" ] && [ $i -lt 60 ]; do sleep 0.5; i=$((i+1)); done; }
start() { "$S/bridge-runner" w1 >/dev/null 2>&1 & RP=$!; echo $RP > "$T/b/runs/w1.pid"; sleep 1.5; }
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

echo; echo "passed: $pass  failed: $fail"; [ $fail = 0 ]
