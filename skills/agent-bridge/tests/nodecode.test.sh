#!/usr/bin/env bash
# nodecode worker: the runner sends an order through bridge-nodecode (`nodecode rpc`, stubbed here), gets the reply back and keeps the session id.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; runner_pid=""
cleanup() { [ -z "$runner_pid" ] || { kill -TERM "$runner_pid" 2>/dev/null || true; wait "$runner_pid" 2>/dev/null || true; }; rm -rf "$T"; }
trap cleanup EXIT
mkdir -p "$T/bin" "$T/br/inbox/admin" "$T/br/inbox/nodecode-1" "$T/br/logs" "$T/home" "$T/work" "$T/.nodecode-1"
printf 'nodecode\n' > "$T/.nodecode-1/provider"
# stub `nodecode rpc [SID]`: one frame stream per start_turn, session id s-STUB (or the one given)
cat > "$T/bin/nodecode" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = rpc ] || exit 2; sid="${2:-s-STUB}"
echo "$*" >> "$STUB_LOG"
while IFS= read -r line; do
  p="$(printf '%s' "$line" | jq -r '.request.prompt')"
  printf '%s\n' "{\"sequence\":1,\"session_id\":\"$sid\",\"payload\":{\"type\":\"session_stream_resumed\"}}"
  printf '%s\n' "{\"sequence\":2,\"session_id\":\"$sid\",\"payload\":{\"type\":\"gateway_turn_command_result\",\"result\":{\"status\":\"accepted\"}}}"
  jq -nc --arg r "stub-reply" --arg sid "$sid" '{sequence:3,session_id:$sid,payload:{frame:{event:{type:"turn.assistant_message_completed",payload:{message:{content:$r}}}}}}'
  jq -nc --arg sid "$sid" '{sequence:4,session_id:$sid,payload:{frame:{event:{type:"turn.completed",payload:{}}}}}'
done
STUB
chmod +x "$T/bin/nodecode"; export STUB_LOG="$T/stub.log"
# 1) the adapter alone: reply on stdout, session id on the last line, resume id passed through
out="$(PATH="$T/bin:$PATH" "$ROOT/scripts/bridge-nodecode" "hola")"
printf '%s\n' "$out" | grep -qx 'stub-reply' || { echo "adapter: no reply: $out" >&2; exit 1; }
[ "$(printf '%s\n' "$out" | tail -1)" = '@@session=s-STUB' ] || { echo "adapter: no session line: $out" >&2; exit 1; }
PATH="$T/bin:$PATH" "$ROOT/scripts/bridge-nodecode" "otra" "s-PREV" >/dev/null
grep -qx 'rpc s-PREV' "$STUB_LOG" || { echo "adapter: session id not passed to rpc" >&2; exit 1; }
# 2) provider detection
[ "$(BRIDGE_DIR="$T/br" "$ROOT/scripts/bridge-provider" "$T/.nodecode-1")" = nodecode ] || { echo "provider != nodecode" >&2; exit 1; }
# 3) runner end to end
printf '%s/.nodecode-1=nodecode-1\n' "$T" > "$T/br/names.conf"; printf 'admin' > "$T/br/admin"
BRIDGE_DIR="$T/br" PATH="$T/bin:$PATH" HOME="$T/home" "$ROOT/scripts/bridge-runner" nodecode-1 > "$T/runner.out" 2>&1 &
runner_pid=$!
sleep 1
BRIDGE_DIR="$T/br" BRIDGE_NAME=admin "$ROOT/scripts/bridge-send" nodecode-1 "di hola" >/dev/null 2>&1 || (cd "$T/work" && BRIDGE_DIR="$T/br" BRIDGE_NAME=admin "$ROOT/scripts/bridge-send" nodecode-1 "di hola" >/dev/null)
for _ in $(seq 1 60); do ls "$T/br/inbox/admin"/* >/dev/null 2>&1 && break; sleep 0.5; done
ls "$T/br/inbox/admin"/* >/dev/null 2>&1 || { cat "$T/runner.out" >&2; echo "no reply reached the admin" >&2; exit 1; }
grep -rq 'stub-reply' "$T/br/inbox/admin" || { cat "$T/br/inbox/admin"/* >&2; echo "reply text missing" >&2; exit 1; }
grep -rq '@@session' "$T/br/inbox/admin" && { echo "session marker leaked into the reply" >&2; exit 1; }
grep -rq 's-STUB' "$T/br/sessions/nodecode-1" || { echo "session id not stored" >&2; exit 1; }
echo "nodecode worker OK"
