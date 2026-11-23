#!/usr/bin/env bash
# `agent update --check` against a fake GitHub (fake curl): ETag/304, rate-limit backoff, shared recent-check cache.
set -e
D="$(cd "$(dirname "$0")/../scripts" && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home"; echo 1.0.0 > "$T/home/version"
cat > "$T/bin/curl" <<'EOS'
#!/usr/bin/env bash
# fake curl: records each call; FAKE_MODE=ok|etag|limit
echo "call" >> "$FAKE_LOG"; out=""; hdr=""; inm=0
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift;; -D) hdr="$2"; shift;; -H) case "$2" in If-None-Match*) inm=1; echo "inm" >> "$FAKE_LOG";; esac; shift;; esac; shift; done
case "$FAKE_MODE" in
  etag) if [ $inm = 1 ]; then printf 'HTTP/2 304\r\netag: "abc"\r\n\r\n' > "$hdr"; : > "$out"; printf 304; else printf 'HTTP/2 200\r\netag: "abc"\r\n\r\n' > "$hdr"; echo '[{"name":"v1.2.0"}]' > "$out"; printf 200; fi;;
  limit) printf 'HTTP/2 403\r\nx-ratelimit-reset: %s\r\n\r\n' "$FAKE_RESET" > "$hdr"; : > "$out"; printf 403;;
esac
EOS
chmod +x "$T/bin/curl"
export PATH="$T/bin:$PATH" BRIDGE_DIR="$T/home" FAKE_LOG="$T/log"; unset AGENT_BRIDGE_TAGS_FILE; : > "$T/log"
fail=0; ok() { echo "  ok   $1"; }; bad() { echo "  FAIL $1"; fail=1; }
calls() { grep -c '^call' "$T/log" || true; }
export FAKE_MODE=etag
out="$("$D/agent-update" --check --json)"; case "$out" in *'"latest":"1.2.0"'*'"available":true'*) ok "first check reads the tags (200)";; *) bad "first: $out";; esac
[ -s "$T/home/update.etag" ] && ok "etag stored" || bad "etag not stored"
"$D/agent-update" --check --json >/dev/null; [ "$(calls)" = 1 ] && ok "second check within 45 s reuses the shared result (no request)" || bad "extra request: $(calls)"
sed -i 's/"checked":[0-9]*/"checked":1/' "$T/home/update.json"
out="$("$D/agent-update" --check --json)"; grep -q inm "$T/log" && ok "later check sends If-None-Match" || bad "no conditional request"
case "$out" in *'"latest":"1.2.0"'*) ok "304 keeps the cached answer";; *) bad "after 304: $out";; esac
export FAKE_MODE=limit FAKE_RESET=$(( $(date +%s) + 3600 )); rm -f "$T/home/update.json" "$T/home/update.etag"; n=$(calls)
out="$("$D/agent-update" --check --json)"; [ -f "$T/home/update.backoff" ] && ok "403 sets a backoff until the reset time" || bad "no backoff"
case "$out" in *'"latest":"1.2.0"'*) ok "still answers from the cache while limited";; *) bad "limited: $out";; esac
rm -f "$T/home/update.json"; n=$(calls); "$D/agent-update" --check --json >/dev/null; [ "$(calls)" = "$n" ] && ok "no requests while backed off" || bad "requested during backoff"
exit $fail
