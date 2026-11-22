#!/usr/bin/env bash
# yerux-skills bootstrap (Linux/macOS/WSL): installs agent-bridge (featured) and any of the other skills.
#   curl -fsSL https://raw.githubusercontent.com/yervix10/yerux-skills/main/get.sh | bash
# Pass installer options after "-s --":  ... | bash -s -- --yes     (or --uninstall, --list, --dry-run)
# Env: AGENT_BRIDGE_REF=<tag|branch|commit> pins a version (default main) · AGENT_BRIDGE_REPO=owner/repo
#      AGENT_BRIDGE_HOME=<dir> (default ~/.agent-bridge) · AGENT_BRIDGE_TARBALL=<file> installs from a local archive
set -eo pipefail
REPO="${AGENT_BRIDGE_REPO:-yervix10/yerux-skills}"; REF="${AGENT_BRIDGE_REF:-main}"; APP="${AGENT_BRIDGE_HOME:-$HOME/.agent-bridge}"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) echo "Windows: use  powershell -c \"irm https://raw.githubusercontent.com/$REPO/$REF/get.ps1 | iex\"" >&2; exit 1;; esac
for c in tar mktemp; do command -v "$c" >/dev/null || { echo "missing: $c" >&2; exit 1; }; done
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
if [ -n "${AGENT_BRIDGE_TARBALL:-}" ]; then cp "$AGENT_BRIDGE_TARBALL" "$tmp/src.tgz"
else command -v curl >/dev/null || { echo "missing: curl" >&2; exit 1; }
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$REF" -o "$tmp/src.tgz" & cp_pid=$!; fr='|/-\\'; i=0
    printf '\033[?25l'; while kill -0 $cp_pid 2>/dev/null; do printf '\r  \033[38;5;81m%s\033[0m Downloading %s@%s ' "${fr:$((i%4)):1}" "$REPO" "$REF"; i=$((i+1)); sleep 0.1; done
    wait $cp_pid && rc=0 || rc=$?; printf '\r\033[K\033[?25h'
    [ $rc = 0 ] || { echo "  download failed (is the repo public and the ref correct?)" >&2; exit 1; }
  else echo "Downloading $REPO@$REF ..."; curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$REF" -o "$tmp/src.tgz" || { echo "download failed (is the repo public and the ref correct?)" >&2; exit 1; }; fi; fi
mkdir "$tmp/x"; tar -xzf "$tmp/src.tgz" -C "$tmp/x"
src="$(ls -d "$tmp"/x/*/ 2>/dev/null | head -1)"; src="${src%/}"
[ -n "$src" ] && [ -f "$src/install.sh" ] && [ -f "$src/skills/agent-bridge/package.sh" ] || { echo "installer files not found in the archive" >&2; exit 1; }
rm -rf "$APP/app"; mkdir -p "$APP"; cp -R "$src" "$APP/app"; chmod +x "$APP/app/skills/agent-bridge/scripts/"* "$APP/app/install.sh"
rm -rf "$tmp"; trap - EXIT
export AGENT_BRIDGE_REF_USED="$REF"
exec bash "$APP/app/install.sh" "$@"
