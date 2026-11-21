# yerux - skills

A collection of Agent Skills for Claude Code and Codex, with a one-line installer.
**agent-bridge** is the featured package (sessions from different accounts that talk to each other); every other
folder with a `SKILL.md` is an optional skill you can tick in the installer.

## Install

    curl -fsSL https://raw.githubusercontent.com/yervix10/yerux-skills/main/get.sh | bash
    powershell -c "irm https://raw.githubusercontent.com/yervix10/yerux-skills/main/get.ps1 | iex"

The installer finds your Claude Code / Codex accounts and opens a menu:
`↑ ↓` move · `space` select · `enter` continue (`r` renames and `+` adds an account on the first page).
Without a terminal it installs agent-bridge into every account found. Options after `bash -s --`:

    --yes                     no menu
    --skills a,b | all | none extra skills to install (default: none)
    --list | --dry-run | --uninstall (removes agent-bridge only)

On Windows pass the same options with `$env:AGENT_BRIDGE_ARGS='-Yes -Skills all'`.
Pin a version with `AGENT_BRIDGE_REF=<tag>`.

From a clone: `./install.sh` (Linux/macOS/WSL) or `.\install.ps1` (Windows). Details: [agent-bridge/README.md](agent-bridge/README.md).
