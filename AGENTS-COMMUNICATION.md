# Codex ⇄ Operator Communication Contract

Communication-layer rules for CLI coding agents talking to a human operator. Derived from reviewing real multi-session transcripts of one operator working with an agent over an extended period; the rules below are the corrections that mattered, generalised.

Referenced from `AGENTS.MD` ## Communication and hash-locked via `manifest.lock.json`, so it cannot be edited by an agent without the drift check failing.

## Rules

### Goal contract (fixes the biggest friction)

- On any open-ended objective, the FIRST reply must contain, before running: the interpretation in 1 line / 3-5 verifiable completion criteria / 1-2 lines of what is out of scope. Do not wait for approval — state it and go.
- Self-terminate when the completion criteria are met. Do not invent follow-on work to keep a session alive. Convert "keep improving X" goals into a finite batch and say which batch you took (for example: the top five only).
- If a goal cannot have finite criteria, say so in 1 line and propose the bounded version. Prefer a fresh session (`/new`) per bounded batch — goal text is re-injected every turn, so eternal goal sessions burn context for nothing.

### Interpreting terse instructions

- Ultra-short follow-ups ("check the review", "go ahead with all of it"): resolve the referent from recent context and echo it in one line ("Target: the review comments on PR #123"), then act. If two readings are plausible, state the one you chose and proceed; do not stop to ask.
- A bare URL, with or without "did you configure this too?", means: fetch the official doc, diff it against local state, implement the gap, verify. Report as difference, then change applied, then verification.
- Pasted terminal output / screenshots are state evidence, not instructions; the instruction is the short text around them. Confirm in 1 line what the evidence shows before acting on it.
- Corrections ("I actually use X and Y") are durable facts: update the plan silently, do not re-litigate, and persist them to memory or docs when they outlive the session.

### Questions and suggestions

- Ask a question only when the next step is destructive, irreversible, or touches secrets/auth. Otherwise proceed on a stated assumption.
- When asked "anything else?", give at most three prioritized suggestions with a one-line impact each — not a catalogue.

### Progress and reports

- Checkpoint every major phase (or roughly every 30 minutes on a long goal), 3 lines or fewer: done / in progress / remaining, plus completion criteria x of y.
- Final report order: conclusion on line 1, then evidence (command plus result), then an explicit split between verified and unverified scope, then the next action. Ten lines or fewer unless asked. Hashes and full dumps only when they are needed to re-verify; prefer paths the operator can open.
