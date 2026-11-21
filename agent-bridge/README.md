# agent-bridge

## One-line install (see the repo root README)

    curl -fsSL https://raw.githubusercontent.com/yervix10/yerux-skills/main/get.sh | bash
    powershell -c "irm https://raw.githubusercontent.com/yervix10/yerux-skills/main/get.ps1 | iex"

It downloads the project to `~/.agent-bridge` and opens a setup menu (accounts, names, skill, hook, bypass, PATH).
Without a terminal it installs everything detected. Options after `bash -s --`: `--yes`, `--uninstall`, `--list`, `--dry-run`.
Pin a version with `AGENT_BRIDGE_REF=<tag>`. On Windows pass options with `$env:AGENT_BRIDGE_ARGS='-Yes'`.

Connects Claude Code, Codex, and Kiro CLI sessions from different accounts on the same machine.

The desktop widget shows a read-only activity feed when you select an agent card. It refreshes while open and includes the recent admin order, assistant messages, tool actions, and result. From the CLI, use `agent feed <name> [--json] [--limit N] [--since TS]`. The limit applies to the newest events after timestamp sorting; incomplete trailing JSONL records and runner prompt wrappers are ignored. Secret-like values are redacted and event text is capped at 2,000 characters.

The detail-panel capture can be refreshed from the widget folder with `./node_modules/.bin/electron . --capture --capture-feed`; it selects a current dashboard agent and writes `docs/screenshot.png`.

The agent detail panel renders safe lightweight Markdown, code blocks with copy buttons, tool activity, and newest-first live updates. Start the widget from the admin session to enable worker controls; the IPC checks the dashboard agent name and admin marker, then the CLI rechecks admin identity. Model and effort changes take effect on the next order. Claude offers Sonnet and Haiku; Opus requires explicit confirmation. Codex and Kiro model choices come from their CLI model lists. Kiro session context and consumed credits appear when available; Kiro exposes no remaining account-quota measurement, so capacity assigns a fixed normal tier. The interactive admin session's controls are disabled; use `/model` or `/compact` in its terminal. **Compact now** confirms first and queues a worker compaction immediately when idle, or before its next order when busy. The CLI equivalent is `agent compact <worker>` (admin only).

    ./install.sh --list      # detected accounts
    ./install.sh --dry-run
    ./install.sh             # install
    ./install.sh --uninstall

Kiro CLI is detected from `kiro-cli` plus `~/.kiro` (or an existing session store). It receives the automatic name `kiro-N`; `./install.sh --kiro-dir DIR` can select another config directory. Instructions and the skill are installed as `steering/AGENTS.md` and `steering/agent-bridge.md`; Kiro supports global steering in `~/.kiro/steering/`. The runner uses `kiro-cli chat --no-interactive --trust-all-tools --trust-workspace`, `--resume-id` for the saved per-worktree session, and a handoff summary when context compaction is needed. It joins all streamed assistant fragments across tool calls into one complete reply and tells Kiro not to send its own bridge message; the runner sends exactly one reply. Set `BRIDGE_BYPASS=0` (or `--safe`) to restrict tool trust.

## Headless workers

    agent up all      # start runners (except yourself)
    agent status | down | logs <n> | reset <n>

In a git project each worker runs in its own worktree `<project>/.worktrees/<name>` (branch `mejora/<name>`,
ignored via `.git/info/exclude`). Disable with `BRIDGE_WORKTREE=0`. Manage them with `agent wt list | diff <n> | merge <n> --yes | clean <n> --yes`.

Monitoring: `agent status` (idle / WORKING + last tool / LIMITED / NO HEARTBEAT). Env: `BRIDGE_ALERT` (seconds, default 1800),
`BRIDGE_STALL` (no-activity seconds, default 600), `BRIDGE_LIMIT_PAUSE` (default 300). Check the install with `./install.sh --check`.
The admin has `/dashboard` (a single snapshot, `agent dashboard --once`) and `agent model <worker> <model|default> [effort]` / `agent effort <worker> <level|default>` (only the admin; applies from the worker's next order; the dashboard shows the effort in use).
The installer wraps each Claude account's status line by default so the dashboard has its numbers (`--no-statusline` skips it).
`agent capacity [--apply]` tells the admin how much work each worker can take from its 5h/weekly/monthly limits (tier skip/light/normal/heavy, suggested load share) and which model/effort to give it; `--apply` sets them.
`agent refresh [name|all]` makes one tiny request per Claude account so the dashboard has fresh numbers (a few tokens each).
On setups that keep a per-session status line cache (`~/.cache/lordos/claude/*.json`) the interactive agents are read from it automatically.
`agent dashboard` shows every agent live, like the status line: `model | project | branch | ctx % | 5h % (↻ time to reset) | sem % (↻) | mes % (↻)` + its state (`mes` only when the provider has a monthly window).
Runners compact their context before an order once it reaches `COMPACT_AT` % (default 40, `0` disables; set in `~/.claude-bridge/config` or `BRIDGE_COMPACT_AT`).
Codex data comes from its latest session file; Kiro data comes from its session history; Claude data from the worker's live log, or from the real status line JSON if you install
with `./install.sh --statusline` (wraps the account's status line, which keeps looking the same; `--uninstall` restores it). Desktop notifications on alerts/limits/errors (`BRIDGE_NOTIFY=0` to mute).
`BRIDGE_REASSIGN=1` (or `REASSIGN=1` in config): when a worker hits a usage limit its order goes to an idle worker.
`./install.sh --safe` / `BRIDGE_BYPASS=safe`: workers can edit files but Claude cannot run arbitrary commands unprompted.
`./install.sh --check --fix` repairs only the accounts that fail the check. Tests: `tests/run.sh` (also run by CI).

## Windows

    powershell -ExecutionPolicy Bypass -File .\install.ps1 -List
    powershell -ExecutionPolicy Bypass -File .\install.ps1

Windows options: `-Check` (verify the install), `-Safe`, `-Yes`, `-DryRun`, `-NoBypass`, `-NoPath`, `-NoTrust` (do not pre-approve the Codex hooks; needs python on PATH).
Runtime: `agent-bridge/windows/bridge.ps1` (PowerShell 5.1+). It adds `agent` and `admin` commands to your PATH.
Accounts inside WSL are installed by running `./install.sh` from WSL.

## Options (Linux/macOS/WSL)

    ./install.sh --claude-dir DIR --codex-dir DIR --kiro-dir DIR  # accounts in custom locations
    ./install.sh --no-trust                          # do not pre-approve the hooks in Codex
    ./install.sh --name DIR=NAME                     # choose a name
Accounts are also found via CLAUDE_CONFIG_DIR / CODEX_HOME / KIRO_HOME in your environment and shell aliases.

## Adding a provider

`bridge-provider` resolves an explicit `provider` file first, then the standard `.claude*`, `.codex*`, or `.kiro*` config prefix. Implement command/resume/model/effort/compact behavior in `bridge-runner`, optional usage in `bridge-usage`, feed parsing in `bridge-feed`, validation in `agent`, widget capabilities and account steering in the installers. Keep unavailable quotas optional. This is the short adapter checklist for a future OpenCode provider.
