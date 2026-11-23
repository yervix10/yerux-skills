---
description: Take command as orchestrator; the other sessions obey you
argument-hint: [who | release]
allowed-tools: Bash(~/.claude-bridge/bin/agent:*), Bash(~/.claude-bridge/bin/admin:*)
---
Use the `agent-bridge` skill. Run `~/.claude-bridge/bin/admin $ARGUMENTS` and show the output.

With no arguments (`/admin` alone), this session becomes the ADMIN and must act as the orchestrator as the skill describes, and it also does these two steps right away, without asking:

1. Run `~/.claude-bridge/bin/agent up all` to start the runner of every worker (already running ones are reported as "already up"). Then run `~/.claude-bridge/bin/agent status` and show which workers are UP.
2. Start `~/.claude-bridge/bin/agent listen` **in the background** (`run_in_background`) so the replies of the workers wake this session. Only one `agent listen` may run at a time: if one is already running in this session, do not start a second one. Each time it returns, read the reports and start it again.

With `who` or `release`, only run the command and show its output.
