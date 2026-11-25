#!/usr/bin/env bash
# agent disable/enable: a blocked worker gets no orders, `up` skips it and the dashboard reports it
set -e
D="$(cd "$(dirname "$0")/../scripts" && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export BRIDGE_DIR="$T"; mkdir -p "$T/inbox/w1" "$T/inbox/adm" "$T/runs"
printf '/x/a=adm\n/x/w=w1\n' > "$T/names.conf"; printf 'adm' > "$T/admin"; export BRIDGE_NAME=adm
"$D/bridge-send" w1 hola >/dev/null || { echo "FAIL: send before disable"; exit 1; }
"$D/agent" disable w1 | grep -q "w1: disabled" || { echo "FAIL: disable"; exit 1; }
if "$D/bridge-send" w1 hola 2>/dev/null; then echo "FAIL: send to a disabled agent was accepted"; exit 1; fi
"$D/bridge-send" all hola >/dev/null; [ "$(ls "$T/inbox/w1" | wc -l)" = 1 ] || { echo "FAIL: 'all' reached a disabled agent"; exit 1; }
"$D/agent" up w1 | grep -q "disabled" || { echo "FAIL: up did not skip"; exit 1; }
"$D/agent" status | grep -q "w1: DISABLED" || { echo "FAIL: status"; exit 1; }
"$D/agent" disable adm 2>&1 | grep -q "cannot be" || { echo "FAIL: admin disabled"; exit 1; }
"$D/agent" enable w1 | grep -q "enabled" && sleep 1 && "$D/agent" down w1 >/dev/null 2>&1 && "$D/bridge-send" w1 hola >/dev/null || { echo "FAIL: enable"; exit 1; }
echo "disable.test.sh: ok"
