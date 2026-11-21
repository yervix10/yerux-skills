---
description: Show every agent: model, project, branch, context %, 5h and weekly usage, and state
allowed-tools: Bash(~/.claude-bridge/bin/agent:*)
---
Use the `agent-bridge` skill. Run `~/.claude-bridge/bin/agent dashboard --once` with Bash and show its output as a table
(one row per agent: model, project, branch, context, 5h limit, weekly limit, state). Add nothing else unless something needs attention
(an agent LIMITED, WORKING for a long time, NO HEARTBEAT, or a limit above 85%).
