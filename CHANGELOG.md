# Changelog

Notable changes to the whole repository, newest first.

## 1.8.1

- `agent enable <worker>` (and the widget's "Activar agente") now also starts the worker's runner.
- Windows (`bridge.ps1`): `agent disable` / `agent enable` with the same rules (blocked workers get no orders, `agent up` and `agent all` skip them, `agent status` shows `DISABLED`).

## 1.8.0

- `agent disable <worker>` / `agent enable <worker>` (admin only): a blocked worker has its runner stopped, `agent up` skips it, and `agent <worker> ...` / `agent all ...` refuse to send it orders until it is enabled again. `agent status` shows `DISABLED`; `agent dashboard --json` adds `disabled` and state `disabled`.
- Widget: "Bloquear agente" / "Activar agente" button in each worker's controls (with confirmation to block); a blocked card shows "Bloqueado" and its model/effort/compact controls are locked.

## 1.7.2

- Widget: the collapse/expand button icon is a CSS chevron, centred in its button (the `⌃` text glyph sat off-centre and depended on the font).

## 1.7.1

- Widget: accepts `nodecode` workers (its parser rejected the unknown kind and showed "Sin conexión con el bridge" for the whole dashboard), with a Nodecode badge.

## 1.7.0

- New worker type: **Nodecode** (`nodecode`, https://nodecode.ai). `nodecode-N` workers run each order as one turn of `nodecode rpc` (JSON lines) through the new `scripts/bridge-nodecode`, resume the same Nodecode session per working directory, and work with the free tier (it runs one request at a time). Marker folders `~/.nodecode-1`, `~/.nodecode-2`, ... (`provider` = `nodecode`) are discovered by `install.sh`, created with `--nodecode-workers N`, or auto-created once when the `nodecode` binary is installed (`BRIDGE_NODECODE_AUTO=0` disables it).
- `agent model <nodecode-N> [PROVIDER/]MODEL` passes the model to the turn; effort is not configurable. No quota meter and no context percentage: Nodecode trims its own context, and `agent compact` just starts a fresh session. Linux/macOS only for now (the Windows runner is unchanged).
- Test: `tests/nodecode.test.sh` (stubbed `nodecode rpc`, end to end through the runner).

## 1.6.12

- OpenCode workers: the context window is read from the model itself (`opencode models --verbose`, `limit.context`) and cached in `runs/opencode-window.<model>`, instead of assuming 128000. Order of precedence: `BRIDGE_OPENCODE_WINDOW`, `OPENCODE_WINDOW=` in `~/.claude-bridge/config`, the model's real window, 128000. With the wrong window the percentage was inflated and the 40 % compaction fired far too early (a 1M-token model was compacted at ~51k tokens).

## 1.6.11

- OpenCode/Copilot context window is configurable in `~/.claude-bridge/config` (`OPENCODE_WINDOW=200000`, `COPILOT_WINDOW=...`), so the setting survives runner restarts. The env vars `BRIDGE_OPENCODE_WINDOW` / `BRIDGE_COPILOT_WINDOW` still take precedence. The default stays 128000, which overstated the context percentage for models with a larger window.

## 1.6.10

- Fixed: OpenCode and Copilot workers never compacted their context. `maybe_compact` had no branch for them and fell into the Codex path (`codex exec resume`), which failed, so the context grew past 100 %. OpenCode now writes a handoff from its own session (fresh session with the summary; fresh session without it if the handoff fails); Copilot starts a fresh session at the threshold.

## 1.6.9

Windows installer, tested on a Windows Server 2022 VM (Windows PowerShell 5.1):
- Fix: the one-liner failed on stock Windows client editions (execution policy `Restricted`) when it started `install.ps1`; the installer now runs in a child PowerShell with a process-scoped `Bypass` (no administrator rights) and explains when an organisation policy forbids it.
- Fix: a file of an older copy held by an antivirus or another process aborted the update half-way; it now retries, and otherwise updates in place file by file and lists what stayed in use.
- Fix: `AGENT_BRIDGE_ARGS` with a single argument (e.g. `-Yes`) failed with a "name" argument error.
- Fix: the Windows banner always said v1.4.0; it now shows the real version.
- Fix: no more "The handle is invalid" when the installer has no console window.
- When no agent CLI is found, a "No agent found" box explains what to do (Linux/macOS and Windows) instead of "0 account(s) configured".
- `OPENCODE_PAID=1` in `~/.claude-bridge/config` allows paid OpenCode models and survives runner restarts (the env var `BRIDGE_OPENCODE_PAID=1` still works).

## 1.6.8

- Faster update notices: the widget checks every 60 s while visible (5 min when hidden or minimized, +-10% jitter) instead of every 15 min. Updates are still never applied without the user choosing to.
- `agent update --check` uses a conditional request (ETag: a 304 costs no GitHub rate limit), backs off until X-RateLimit-Reset after a 403/429 while serving the cached tag list, and shares one cache across the widget, the CLI and listeners (a result under 45 s old is reused).

## 1.6.7

- Fix: a worker whose account is signed out stays "Sesión caída" across runner restarts (marker `runs/<name>.auth`, cleared when an order succeeds); before, restarting the runner made it look "Libre" again.
- Widget: removed the grip dots (the whole header still drags the window) and moved the version next to the title.

## 1.6.6

- Fix: the widget rejected the whole dashboard (showing "Sin conexión con el bridge") as soon as one worker was in the `auth` state; its validator now accepts `auth`, and a test checks every state `agent` can emit against it.
- Fix: `agent dashboard` no longer prints bash arithmetic errors when a usage value is `-`.

## 1.6.5

- Widget: optional dark mode (header button, remembered; light stays the default and nothing follows the system).
- Widget: the header summary wraps instead of being cut off at narrow widths; "Agent Bridge" no longer splits.
- Widget: the whole header drags the window, not only the grip dots.

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
