---
description: Talk to a specific session (ping, order, all, listen, up/down/status)
argument-hint: ping <target> | <target> <message> | all <message> | listen | up|down <name|all> | status | dashboard --once | model <worker> <model|default> | logs <name> | reset <name> | list | inbox
allowed-tools: Bash(~/.claude-bridge/bin/agent:*)
---
Use the `agent-bridge` skill. Arguments: `$ARGUMENTS`

- If the first one is `listen`: run `~/.claude-bridge/bin/agent listen` with Bash in the **background**; when it finishes it brings messages: handle them according to their label and launch `listen` again.
- Otherwise: run `~/.claude-bridge/bin/agent $ARGUMENTS` and show the output without adding anything.
