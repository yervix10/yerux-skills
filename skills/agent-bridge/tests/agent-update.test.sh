#!/usr/bin/env bash
# Offline tests for `agent update --check` (fake GitHub tags list; no network, no installs).
set -e
D="$(cd "$(dirname "$0")/../scripts" && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export BRIDGE_DIR="$T" AGENT_BRIDGE_TAGS_FILE="$T/tags.json"
fail=0; ok() { echo "  ok   $1"; }; bad() { echo "  FAIL $1"; fail=1; }
echo '[{"name":"v1.4.0"},{"name":"v1.10.0"},{"name":"v1.9.2"},{"name":"nightly"},{"name":"v1.11.0-rc1"}]' > "$T/tags.json"
echo 1.5.0 > "$T/version"
out="$("$D/agent-update" --check --json)"
case "$out" in *'"latest":"1.10.0"'*'"available":true'*) ok "newest semver tag wins (1.10.0 > 1.9.2), non-release tags ignored";; *) bad "latest: $out";; esac
[ -f "$T/update.json" ] && ok "update.json cached" || bad "update.json missing"
echo 1.10.0 > "$T/version"
case "$("$D/agent-update" --check --json)" in *'"available":false'*) ok "no update when already on the latest";; *) bad "false positive";; esac
echo 2.0.0 > "$T/version"
case "$("$D/agent-update" --check --json)" in *'"available":false'*) ok "no downgrade when ahead of the latest tag";; *) bad "downgrade offered";; esac
echo '[]' > "$T/tags.json"
"$D/agent-update" --check >/dev/null && ok "--check never fails without tags" || bad "--check failed without tags"
echo 1.0.0 > "$T/version"; echo '[{"name":"v1.1.0"}]' > "$T/tags.json"
if "$D/agent-update" </dev/null >/dev/null 2>&1; then bad "applied without confirmation"; else ok "refuses to install without --yes and no terminal"; fi
exit $fail
