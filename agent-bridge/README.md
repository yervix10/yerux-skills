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

## Windows

    powershell -ExecutionPolicy Bypass -File .\install.ps1 -List
    powershell -ExecutionPolicy Bypass -File .\install.ps1

Runtime: `agent-bridge/windows/bridge.ps1` (PowerShell 5.1+). It adds `agent` and `admin` commands to your PATH.
Accounts inside WSL are installed by running `./install.sh` from WSL.

## Options (Linux/macOS/WSL)

    ./install.sh --claude-dir DIR --codex-dir DIR    # accounts in custom locations
    ./install.sh --name DIR=NAME                     # choose a name
Accounts are also found via CLAUDE_CONFIG_DIR / CODEX_HOME in your environment and shell aliases.
