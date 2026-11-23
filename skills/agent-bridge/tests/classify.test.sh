#!/usr/bin/env bash
# Tests for the runner's classify(): login/session errors must be "auth", not a generic "api" error.
set -e
D="$(cd "$(dirname "$0")/../scripts" && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
sed -n '/^classify() {/,/^  echo ok; }/p' "$D/bridge-runner" > "$T/classify.sh"; . "$T/classify.sh"
fail=0; t() { got="$(classify "$1" "$2")"; if [ "$got" = "$3" ]; then echo "  ok   $3 <- ${2:0:48}"; else echo "  FAIL expected $3 got $got <- $2"; fail=1; fi; }
t 1 "API ERROR: Not logged in · Please run /login" auth
t 1 "Invalid API key · Please run /login" auth
t 1 "OAuth token has expired. Please obtain a new token" auth
t 1 "HTTP 401 Unauthorized" auth
t 1 "authentication required" auth
t 1 "Overloaded, try again" api
t 0 "tests e1401 and e1402 pass; HTTP 401 handling documented" ok
t 1 "test e1300 failed: expected output differs" error
t 1 "FAILED: not scoped to a workspace" api
t 1 "503 service unavailable" api
t 1 "You've hit your usage limit" limit
t 0 "all good, 12 tests passed" ok
t 124 "" timeout
t 1 "segfault" error
exit $fail
