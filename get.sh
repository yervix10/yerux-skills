#!/usr/bin/env bash
# yerux-skills bootstrap (Linux/macOS/WSL): installs the skills and, from the separate yerux-agent-bridge project, agent-bridge (featured).
#   curl -fsSL https://raw.githubusercontent.com/yervix10/yerux-skills/main/get.sh | bash
# Pass installer options after "-s --":  ... | bash -s -- --yes     (or --uninstall, --list, --dry-run)
# Env: AGENT_BRIDGE_REF=<tag|branch|commit> pins a version (default main) · AGENT_BRIDGE_REPO=owner/repo
#      AGENT_BRIDGE_HOME=<dir> (default ~/.agent-bridge) · AGENT_BRIDGE_TARBALL=<file> installs from a local archive
#      AGENT_BRIDGE_APP_REPO=owner/repo (default yervix10/yerux-agent-bridge) · AGENT_BRIDGE_APP_REF=<tag|branch> (default main)
#      AGENT_BRIDGE_APP_TARBALL=<file> local archive of the agent-bridge project · AGENT_BRIDGE_DIR=<dir> use an existing checkout (nothing is downloaded)
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
[ -n "$src" ] && [ -f "$src/install.sh" ] || { echo "installer files not found in the archive" >&2; exit 1; }
rm -rf "$APP/app"; mkdir -p "$APP"; cp -R "$src" "$APP/app"; chmod +x "$APP/app/install.sh"
# agent-bridge lives in its own project: download it next to the installer unless an existing checkout is given
if [ -z "${AGENT_BRIDGE_DIR:-}" ]; then
  APP_REPO="${AGENT_BRIDGE_APP_REPO:-yervix10/yerux-agent-bridge}"; APP_REF="${AGENT_BRIDGE_APP_REF:-main}"
  if [ -n "${AGENT_BRIDGE_APP_TARBALL:-}" ]; then cp "$AGENT_BRIDGE_APP_TARBALL" "$tmp/app.tgz"
  else curl -fsSL "https://codeload.github.com/$APP_REPO/tar.gz/$APP_REF" -o "$tmp/app.tgz" 2>/dev/null || rm -f "$tmp/app.tgz"; fi
  if [ -s "$tmp/app.tgz" ]; then mkdir "$tmp/y"; tar -xzf "$tmp/app.tgz" -C "$tmp/y"; absrc="$(ls -d "$tmp"/y/*/ 2>/dev/null | head -1)"; absrc="${absrc%/}"
    if [ -n "$absrc" ] && [ -f "$absrc/bridge/package.sh" ]; then rm -rf "$APP/yerux-agent-bridge"; cp -R "$absrc" "$APP/yerux-agent-bridge"; chmod +x "$APP/yerux-agent-bridge/bridge/scripts/"*
    else echo "warning: $APP_REPO has no bridge/package.sh; installing the skills only" >&2; fi
  else echo "warning: could not download $APP_REPO@$APP_REF; installing the skills only (set AGENT_BRIDGE_DIR to use a local checkout)" >&2; fi
fi
rm -rf "$tmp"; trap - EXIT
export AGENT_BRIDGE_REF_USED="$REF"
exec bash "$APP/app/install.sh" "$@"
