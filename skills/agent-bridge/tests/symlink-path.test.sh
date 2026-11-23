#!/usr/bin/env bash
# `agent` must find its sibling scripts when launched through a chain of symlinks (~/.local/bin -> ~/.claude-bridge/bin -> app).
set -e
S="$(cd "$(dirname "$0")/../scripts" && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/a" "$T/b" "$T/home"; : > "$T/home/names.conf"; ln -s "$S/agent" "$T/a/agent"; ln -s "$T/a/agent" "$T/b/agent"
out="$(cd /tmp && BRIDGE_DIR="$T/home" "$T/b/agent" status 2>&1 || true)"
case "$out" in *"No such file"*|*"No existe"*) echo "FAIL: $out"; exit 1;; esac
echo "  ok   agent works through a symlink chain"
