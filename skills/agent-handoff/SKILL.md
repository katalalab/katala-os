---
name: agent-handoff
description: Write a structured handoff document so another agent (Claude, Codex, Antigravity) can continue the current work session without loss of context. Use when switching agents mid-task, closing a long session, or handing off to a fleet peer node.
---

# agent-handoff — structured agent context transfer

Produces a handoff note at `~/work/docs/handoffs/<topic>/<date>-handoff.md` that lets any receiving agent resume without reading the full conversation.

## When to use

- "手を離す前に引き継ぎ書いて"
- "Codex に渡したい、ハンドオフして"
- "このセッションを Antigravity で続けたい"
- End-of-session wrap-up for long tasks

Do **not** use for:
- Simple status summaries (use `/session-report` instead)
- PR descriptions (use `commit-commands:commit-push-pr`)

## Output structure

```markdown
# Handoff: <topic>
Date: YYYY-MM-DD  Agent: <source>  Target: <destination>

## State
What is done, what is in-progress, what is blocked.

## Minimum Restart Path
Ordered steps for the receiving agent to pick up correctly.

## Open Questions
Decisions deferred to the receiving agent or operator.

## Files Changed
Paths + one-line summaries.

## Verification Commands
Narrowest real commands to confirm health.
```

## How to invoke

1. Read the current conversation state and any open task lists.
2. Write the handoff file under `~/work/docs/handoffs/<topic>/`.
3. Print the absolute path and the Minimum Restart Path to the terminal.
4. If routing to Codex: suggest `codex --context <path>` invocation.

## Hard-rule reminders

- Never include secrets, tokens, or credentials in the handoff file.
- State verified vs. unverified scope separately.
- Include a rollback command for any destructive change performed in the session.
