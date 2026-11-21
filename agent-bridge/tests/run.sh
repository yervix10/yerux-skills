#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash -n "$ROOT/scripts/bridge-runner" "$ROOT/scripts/admin" "$ROOT/package.sh" "$ROOT/tests/bridge-security.test.sh"
"$ROOT/tests/bridge-security.test.sh"
node --test "$ROOT/widget/test/feed.test.cjs"
(cd "$ROOT/widget" && npm test)
