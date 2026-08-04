# Codex ⇄ Operator Communication Contract

Communication-layer rules for Codex (and other CLI agents) talking to the operator on the Katala OS fleet. Derived from analysis of 29 real Codex sessions (`~/.codex/sessions/`, 2026-06-03 → 2026-07-01: 98 operator messages, 2,209 assistant messages).

Status: RATIFIED 2026-07-27 by operator (explicit ratification via named question). Referenced from `AGENTS.MD` ## Communication and hash-locked via `manifest.lock.json`. Agents honor the Rules below fleet-wide.

## Observed communication profile (evidence, keep for context)

Operator:

- Japanese, imperative, very short — often under 30 chars（「全部進めて」「走り切ってください」「WARNを全て解消してください」「レビューを確認して」）.
- States outcomes, not procedures. Goals are often huge or open-ended（「SSH接続ができる全てのマシンのファイルを分析し、俺の人生を最高にしてほしいです」「自分の環境のブラッシュアップ」「最高の設定」）.
- Pastes bare URLs, screenshots, and raw terminal output as context; expects the agent to resolve what they mean（「これの設定も完了した？」）.
- Grants broad latitude up front（「PRを作成してGithubに投げても良いよ」）; corrections are terse facts（「RustDeskとParsecは使っています」）.
- Heavy `/goal` user. Longest session ran 30 turns / 560 assistant messages / 11 auto-compactions until the operator had to say 「完了条件を決めて終了してください」— the single biggest observed friction.

Codex:

- Japanese narration (median 88 chars), evidence-dense final reports (paths, commands, hashes).
- Almost never asks questions (3 of 2,209 messages) — good momentum, but with open-ended goals it runs unbounded instead of converging.

## Rules

### Goal contract (fixes the biggest friction)

- On any `/goal` or open-ended objective, the FIRST reply must contain, before running: 解釈 1 line / 完了条件 3–5 verifiable checks / スコープ外 1–2 lines. Do not wait for approval — state and go.
- Self-terminate when the 完了条件 are met. Do not invent follow-on work to keep a goal session alive. 「改善し続ける」系のゴールは有限バッチに変換して宣言する（例: 今回は上位5件のみ）.
- If a goal cannot have finite criteria, say so in 1 line and propose the bounded version. Prefer a fresh session (`/new`) per bounded batch — goal text is re-injected every turn, so eternal goal sessions burn context for nothing.

### Interpreting terse instructions

- Ultra-short follow-ups（「レビューを確認して」「全部進めて」）: resolve the referent from recent context and echo it in 1 line（例: 「対象: CodexBar PR #1291/#1292 のレビューコメント」）, then act. If two readings exist, state the chosen one and proceed; do not stop to ask.
- Bare URL (± 「これの設定も完了した？」) = "fetch the official doc, diff against local state, implement the gap, verify". Report as 差分 → 適用 → 検証.
- Pasted terminal output / screenshots are state evidence, not instructions; the instruction is the short text around them. Confirm in 1 line what the evidence shows before acting on it.
- Corrections（「XとYは使っています」）are durable facts: update the plan silently, don't re-litigate, persist to memory/docs when they outlive the session.

### Questions and suggestions

- Ask a question only when the next step is destructive, irreversible, or touches secrets/auth. Otherwise proceed on a stated assumption.
- When asked 「他にある？」, give at most 3 prioritized suggestions with 1-line impact each — not a catalog.

### Progress and reports

- Checkpoint every major phase (or ~30 min in goal mode), ≤3 lines: 完了 / 進行中 / 残り, plus 完了条件 x/y in goal sessions.
- Final report order: 結論 (line 1) → 証拠 (command + result) → 検証済み/未検証の区別 → 次アクション. ≤10 lines unless asked. Hashes and full dumps only when needed to re-verify; prefer paths the operator can open.
