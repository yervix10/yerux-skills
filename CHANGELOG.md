# Changelog

## 1.5.0 (unreleased)
- New worker types: **Antigravity** (`agy-N`, `agy -p`), **Cursor CLI** (`cursor-N`, `cursor-agent -p`), **GitHub Copilot CLI** (`copilot-N`, `copilot -p`) and
  **OpenCode** (`opencode-N`, `opencode run`), with the Kiro pattern: provider marker, runner (resume by session id, handoff compaction, LIMIT/API ERROR
  classification, live feed and activity), model validation, dashboard/widget kinds, installers (`--agy-dir`, `--cursor-dir`, `--copilot-dir`,
  `--opencode-dir`, `--opencode-workers N`, check/fix/uninstall) on Linux/macOS and Windows.
- Cursor workers always call `cursor-agent`, never `agent` (the bridge command). The installers warn when Cursor's own `agent` shadows the bridge's.
- OpenCode: several workers share one install and its credentials (`auth.json`); each is a marker folder `~/.opencode-N` with its own model, session and
  worktree. Only `*-free` / `*:free` models are accepted by `agent model` and by the runner unless `BRIDGE_OPENCODE_PAID=1`. The dashboard shows the model and
  the accumulated cost (`cost` of `step_finish`). `Rate limit`, `free-models-per-day`, `Free Usage Limit Reached` and `tokens per minute (TPM)` are LIMIT;
  `not scoped to a workspace` is an API/config error (add the `anthropic-workspace-id` header to `opencode.jsonc`).
- Copilot: tier `light` (every order spends premium requests of the monthly quota; the counter is shown in the dashboard); `Access denied by policy settings` is an API error, not a limit.
- Cursor, Copilot and OpenCode have no quota windows (effort is not configurable for Cursor/OpenCode); context % is estimated from token usage.
- Runner robustness: EAGAIN / `Failed to start ... thread` / exit code 134 are retried up to 3 times (30 s apart, `BRIDGE_RETRY_WAIT`) before the order is reported as failed.
- Tests with fake `agy`, `cursor-agent`, `copilot` and `opencode`.

## 1.3.0
- `agent dashboard` shows per agent what the Claude status line shows: model, project, branch, context %, 5h and weekly usage
  (coloured by how full they are) plus the worker state. Codex agents: read from their latest session file
  (`bridge-usage`). Claude agents: worker live log, or the saved status line JSON with `./install.sh --statusline`
  (a wrapper that keeps the original bar; `--uninstall` restores it). Windows: Codex and Claude worker data, no status line wrapper.

## 1.4.0
- Status line data is on by default at install (`--no-statusline` skips it); `--check` verifies it. Not available on Windows.
- Admin command `/dashboard` (`agent dashboard --once`, plain snapshot; the live view stays `agent dashboard` in a terminal).
- `agent model <worker> <model|default>`: the admin changes the model a worker uses from its next order (`--model` for Claude,
  `-m` for Codex). Only the admin may do it; `agent model` lists them and the dashboard shows the one set.
- Ported to Windows (except the status line wrapper).

## 1.4.1
- `agent effort <worker> <level|default>` (and `agent model <worker> <model> [effort]`): the admin sets each worker's reasoning effort too.
  Claude gets `--effort` (low medium high xhigh max), Codex `-c model_reasoning_effort` (none minimal low medium high xhigh); validated
  per provider. The dashboard shows the effort in use next to the model.

## 1.3.1
- Dashboard: Claude agents now load. Interactive sessions are read from the status line cache when present, workers from their live
  log (now with context % from the usage and the model's window), and `agent refresh` fills the rest with one tiny request per account.

## 1.2.0
- CI (GitHub Actions): shell syntax + `tests/run.sh` on Linux, macOS (best effort), PowerShell parse on Windows.
- Tests now cover Codex workers, reassignment, `agent wt`, and install / `--check` / `--fix` / uninstall in an isolated HOME.
- Codex workers: live JSON log, last action in `agent status`, `STALLED:` and error classification from its events.
- `BRIDGE_REASSIGN=1`: on a usage limit the order goes to an idle worker. `agent dashboard`. Desktop notifications (`BRIDGE_NOTIFY=0` mutes).
- Installer: `--check --fix` repairs only failing accounts, notices a newer upstream version, final box says which accounts were
  "already up to date" vs "updated". `--uninstall` removes the Codex hook approvals it added.
- `--safe` / `BRIDGE_BYPASS=safe` mode for workers.
- Windows: reassign on limit, `agent dashboard`, desktop notifications (balloon tip) and `-Safe` ported (untested on Windows).

## 1.1.0

### Installer
- Step-by-step menu: Packages (with an `all` row) -> Accounts -> agent-bridge -> Confirm. Stepper header, aligned lists,
  selected counter and a summary box. `b` goes back; `e` on the Accounts step opens the editable list (rename, add folder, deselect).
- `--check` verifies scripts, hooks, names, skills and Codex hook approval of every account.
- `--dry-run` shows one line per account (and on Windows no longer writes anything).
- Codex hooks are approved automatically (no `/hooks` needed); `--no-trust` / `-NoTrust` disables it.

### agent-bridge
- Workers run in their own git worktree `<project>/.worktrees/<name>` (branch `mejora/<name>`); `BRIDGE_WORKTREE=0` disables it.
  `agent wt list | diff | merge | clean <name>` manages them (merge/clean need `--yes`).
- No time limit per order (`BRIDGE_TASK_TIMEOUT` sets one).
- Observability: state file + heartbeat (`agent status`), live activity of Claude workers (last tool call), `ALERT:` when an order
  runs long (`BRIDGE_ALERT`), `STALLED:` when there is no activity (`BRIDGE_STALL`), and replies prefixed `LIMIT:` / `API ERROR:` / `ERROR`.
- On a usage limit the worker pauses until the reset time (from the provider, or `BRIDGE_LIMIT_PAUSE`) and keeps queued orders.
- `tests/run.sh`: runner tests with a fake `claude`.

### Windows
- Ported: step menu, dry-run fix, worktrees, hook approval, state/heartbeat/alerts, error classification, live activity and
  `STALLED:`, limit pause, `agent wt` and `-Check`. The Windows code has not been run on Windows yet.
