# Changelog

Notable changes to the whole repository, newest first.

## 1.6.4

- Fix: `agent`, `admin` and the other scripts now follow symlink chains (`~/.local/bin/agent` -> `~/.claude-bridge/bin/agent` -> app) to find their siblings; before, `bridge-whoami` was not found and `agent up all` could start a runner for the admin session itself.
- `agent update` restarts idle runners on the new code (busy ones are listed); runners kept the old code in memory, so e.g. the "Sesión caída" state never showed after an update.
- `agent down all` ignores `.state` files.
- Widget shows the project version where the clock was (hover for the last update time).

## 1.6.3

- macOS: runner time limits fall back to `perl` when `timeout`/`gtimeout` are missing; the installer no longer prints the "no 'timeout'" note unless perl is missing too, and the update check has the same fallback.

## 1.6.2

- `bridge-widget stop` (and `agent update`) now close **every** widget instance, whichever folder it was started from; before, a copy left running from an old folder kept running after the others were stopped. `start` also closes copies of other folders.
- Fixed the harmless `install.sh: line 239: 3: Bad file descriptor` printed after the installer menu.

## 1.6.1

- The widget looks for updates every 15 minutes (was hourly) and has **Buscar actualizaciones** in its tray menu to check right away.

## 1.6.0

- **Mention your agents.** The installer writes one tiny subagent per worker in every Claude account (`~/.claude*/agents/<worker>.md`). Write `@agent-claude-2 do X` (or just "tell claude-2 to do X") and it forwards the task with `agent claude-2 "..."`. Files carry a marker: your own agent files are never overwritten, stale ones are removed, and `--uninstall` removes only ours.

## 1.5.2

- The installer no longer overwrites `~/.claude-bridge/config`: it changes only `BYPASS` and keeps the options you set (`WIDGET`, `ALERT`, `COMPACT_AT`, ...). Updating from the widget therefore keeps your settings.

## 1.5.1

- New state **Sesión caída**: when a worker's order fails because the account is signed out or its session expired, the runner records `auth` (not a generic API error), `agent dashboard --json` reports `state: "auth"`, and the widget shows a clear notice on top.
- The admin card in the widget is soft violet (no left bar).

## 1.5.0

- `agent update [--check] [--yes]`: updates to the newest `vX.Y.Z` tag; the installed version lives in `~/.claude-bridge/version`.
- The widget shows an "update available" banner (hourly check) with an update button, and a close button; flat, light-only look; the admin card no longer has a left bar.
- The installer menu handles arrow keys on macOS terminals (echo is turned off with `stty`).
- `/admin` starts every worker and leaves `agent listen` running.

### Repository
- Every skill, **agent-bridge** included, now lives under `skills/`. Installers, bootstrap scripts, CI and docs follow the new paths.
- Skill names unified as `<topic>-<type>`: `audit` → `neovim-audit`, `palette` → `color-palette`, `review` → `project-review`.
- Removed the `notion` skill and the root `tests/` folder. CI now runs the security and feed tests in `skills/agent-bridge/tests`.
- README and CHANGELOG rewritten to cover the whole repository.

### agent-bridge
- New worker types: **Antigravity** (`agy-N`), **Cursor CLI** (`cursor-N`, always `cursor-agent`, never the bridge's `agent`), **GitHub Copilot CLI** (`copilot-N`) and **OpenCode** (`opencode-N`), each with a runner, session resume, handoff compaction, limit and API-error classification, live feed, model validation, dashboard and widget support, and installers for Linux, macOS and Windows.
- OpenCode: several workers share one install and its credentials, each in a marker folder `~/.opencode-N` with its own model, session and worktree. Only `-free` models are accepted unless `BRIDGE_OPENCODE_PAID=1`; `BRIDGE_OPENCODE_AUTO=0` disables automatic marker creation. The dashboard shows accumulated cost.
- Copilot: tier `light` because every order spends a premium request; the dashboard shows the counter.
- Runner retries up to 3 times on EAGAIN, thread-start failures and exit code 134 before reporting an order as failed.
- Qwen and Gemini CLI support was tried and dropped.
- Security: the bridge's trust boundary (same OS user) is documented; the mailbox is `0700` and admin identity and live logs `0600`.
- Activity feed (`agent feed`) with redaction of secret-like values, and a richer widget detail panel.
- Claude context is kept while a turn is running; quota and native compaction reporting improved; decimal percentages and locale-safe cost formatting.
- Kiro CLI worker (`kiro-N`) with complete replies joined across tool calls and a single bridge response per order.

## 1.4.0
- Status line data is on by default at install (`--no-statusline` skips it); `--check` verifies it. Not available on Windows.

## 1.3.0
- `agent dashboard` shows per agent the model, project, branch, context %, 5h and weekly usage and the worker state, from the status line for Claude and from session files for Codex.

## 1.0 – 1.2
- Initial agent-bridge: file mailbox, hook delivery, `/admin`, `/agent`, headless runners with per-worker worktrees, `agent capacity`, installer with account detection, Windows port, and the first set of skills.
