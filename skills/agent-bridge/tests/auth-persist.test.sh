#!/usr/bin/env bash
# A signed-out account must stay "auth" across runner restarts until an order succeeds (fake `claude`, real runner).
set -e
S="$(cd "$(dirname "$0")/../scripts" && pwd)"; T="$(mktemp -d)"; R=""
trap '[ -n "$R" ] && kill "$R" 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/br/inbox/w-1" "$T/br/runs" "$T/br/logs" "$T/acc/.claude"
cat > "$T/bin/claude" <<'EOS'
#!/bin/sh
if [ -f "$FAKE_OK" ]; then echo "all good"; exit 0; fi
echo "API Error: Not logged in · Please run /login"; exit 1
EOS
chmod +x "$T/bin/claude"; printf '%s=w-1\n' "$T/acc/.claude" > "$T/br/names.conf"; echo admin > "$T/br/admin"
export BRIDGE_DIR="$T/br" PATH="$T/bin:$PATH" FAKE_OK="$T/ok" BRIDGE_WORKTREE=0
cd "$T"
start() { bash "$S/bridge-runner" w-1 >>"$T/run.log" 2>&1 & R=$!; sleep 3; }
stop() { kill "$R" 2>/dev/null; wait "$R" 2>/dev/null || true; R=""; }
order() { printf 'From: admin\nTo: w-1\nDate: x\nCwd: %s\n\nx\n' "$T" > "$T/br/inbox/w-1/2026112316$1-de-admin.msg"; sleep 10; }
kind() { sed -n 's/^last_kind=//p' "$T/br/runs/w-1.state"; }
ck() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3 (got '$1', want '$2')"; exit 1; fi; }
start; order 01; ck "$(kind)" auth "failed order -> auth"
stop; rm -f "$T/br/runs/w-1.state"; start; ck "$(kind)" auth "auth survives a runner restart"
touch "$T/ok"; order 02; ck "$(kind)" ok "a successful order clears it"; [ ! -e "$T/br/runs/w-1.auth" ] && echo "  ok   marker removed"
