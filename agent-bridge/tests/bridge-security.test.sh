#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE="$(mktemp -d)"
runner_pid=""
cleanup() { [ -z "$runner_pid" ] || { kill -TERM "$runner_pid" 2>/dev/null || true; wait "$runner_pid" 2>/dev/null || true; }; rm -rf "$BRIDGE"; }
trap cleanup EXIT
mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

mkdir -p "$BRIDGE/inbox/admin" "$BRIDGE/inbox/worker" "$BRIDGE/logs" "$BRIDGE/.codex"
printf '%s/.codex=worker\n' "$BRIDGE" > "$BRIDGE/names.conf"
printf 'old-admin' > "$BRIDGE/admin"
chmod 644 "$BRIDGE/admin"
BRIDGE_DIR="$BRIDGE" BRIDGE_NAME=worker BRIDGE_WIDGET=0 "$ROOT/scripts/admin" >/dev/null
[ "$(mode "$BRIDGE/admin")" = 600 ] || { echo 'admin file is not mode 600' >&2; exit 1; }

printf 'sensitive transcript\n' > "$BRIDGE/logs/old.live"
chmod 644 "$BRIDGE/logs/old.live"
BRIDGE_DIR="$BRIDGE" "$ROOT/scripts/bridge-runner" worker >"$BRIDGE/runner.out" 2>&1 &
runner_pid=$!
for _ in $(seq 1 50); do
  [ "$(mode "$BRIDGE/logs/old.live")" = 600 ] && break
  sleep 0.1
done
[ "$(mode "$BRIDGE/logs/old.live")" = 600 ] || { cat "$BRIDGE/runner.out" >&2; echo 'live log is not mode 600' >&2; exit 1; }
