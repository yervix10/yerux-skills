# Changelog

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
