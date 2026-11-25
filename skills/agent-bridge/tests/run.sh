#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash -n "$ROOT/scripts/bridge-runner" "$ROOT/scripts/bridge-nodecode" "$ROOT/scripts/admin" "$ROOT/package.sh" "$ROOT/tests/bridge-security.test.sh"
"$ROOT/tests/bridge-security.test.sh"
"$ROOT/tests/nodecode.test.sh"
"$ROOT/tests/disable.test.sh"
node --test "$ROOT/widget/test/feed.test.cjs"
(cd "$ROOT/widget" && npm test)
