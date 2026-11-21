# agent-bridge

## One-line install (see the repo root README)

    curl -fsSL https://raw.githubusercontent.com/yervix10/yerux-skills/main/get.sh | bash
    powershell -c "irm https://raw.githubusercontent.com/yervix10/yerux-skills/main/get.ps1 | iex"

It downloads the project to `~/.agent-bridge` and opens a setup menu (accounts, names, skill, hook, bypass, PATH).
Without a terminal it installs everything detected. Options after `bash -s --`: `--yes`, `--uninstall`, `--list`, `--dry-run`.
Pin a version with `AGENT_BRIDGE_REF=<tag>`. On Windows pass options with `$env:AGENT_BRIDGE_ARGS='-Yes'`.

Connects Claude Code and Codex sessions from different accounts on the same machine.

    ./install.sh --list      # detected accounts
    ./install.sh --dry-run
    ./install.sh             # install
    ./install.sh --uninstall

## Headless workers

    agent up all      # start runners (except yourself)
    agent status | down | logs <n> | reset <n>

In a git project each worker runs in its own worktree `<project>/.worktrees/<name>` (branch `mejora/<name>`,
ignored via `.git/info/exclude`). Disable with `BRIDGE_WORKTREE=0`. Manage them with `agent wt list | diff <n> | merge <n> --yes | clean <n> --yes`.

Monitoring: `agent status` (idle / WORKING + last tool / LIMITED / NO HEARTBEAT). Env: `BRIDGE_ALERT` (seconds, default 1800),
`BRIDGE_STALL` (no-activity seconds, default 600), `BRIDGE_LIMIT_PAUSE` (default 300). Check the install with `./install.sh --check`.
Tests: `tests/run.sh`.

## Windows

    powershell -ExecutionPolicy Bypass -File .\install.ps1 -List
    powershell -ExecutionPolicy Bypass -File .\install.ps1

Windows options: `-Yes`, `-DryRun`, `-NoBypass`, `-NoPath`, `-NoTrust` (do not pre-approve the Codex hooks; needs python on PATH).
Runtime: `agent-bridge/windows/bridge.ps1` (PowerShell 5.1+). It adds `agent` and `admin` commands to your PATH.
Accounts inside WSL are installed by running `./install.sh` from WSL.

## Options (Linux/macOS/WSL)

    ./install.sh --claude-dir DIR --codex-dir DIR    # accounts in custom locations
    ./install.sh --no-trust                          # do not pre-approve the hooks in Codex
    ./install.sh --name DIR=NAME                     # choose a name
Accounts are also found via CLAUDE_CONFIG_DIR / CODEX_HOME in your environment and shell aliases.
