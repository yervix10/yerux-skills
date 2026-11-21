---
description: Take command as orchestrator; the other sessions obey you
argument-hint: [who | release]
allowed-tools: Bash(~/.claude-bridge/bin/agent:*), Bash(~/.claude-bridge/bin/admin:*)
---
Use the `agent-bridge` skill. Run `~/.claude-bridge/bin/admin $ARGUMENTS` and show the output. With no arguments, this session becomes the ADMIN and must act as the orchestrator as the skill describes.
