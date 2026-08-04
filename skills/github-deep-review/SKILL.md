---
name: github-deep-review
description: Deep review of a GitHub PR or commit — traces call paths, checks for regressions, security issues, data loss risks, and missing tests. More thorough than a surface diff review. Use when the operator wants a comprehensive pre-merge analysis.
---

# github-deep-review — comprehensive PR/commit analysis

Performs a multi-layer review: diff reading → call-path tracing → risk assessment → test coverage check.

## When to use

- "この PR を深くレビューして"
- "マージ前に regression リスクを確認して"
- "セキュリティ観点で見てほしい"
- "テストが十分か確認して"

Do **not** use for:
- Quick style or formatting checks (use `/code-review` instead)
- Reviewing your own just-written code (too much context bias)

## Review layers

### 1. Diff surface

```bash
gh pr diff <pr-number>
gh pr view <pr-number> --json title,body,files,reviews,checksums
```

### 2. Call-path impact

Use `code_mapper` subagent or `rg` to trace callers of changed functions.

### 3. Risk dimensions (report each separately)

- **Correctness**: logic errors, off-by-one, null handling
- **Regressions**: changed behavior in existing callers
- **Security**: injection, auth bypass, secret exposure, SSRF
- **Data loss**: destructive ops, migration safety, rollback path
- **Concurrency**: race conditions, lock order, shared state mutation
- **Test coverage**: uncovered branches, missing edge cases

### 4. Verdict

```
APPROVE / REQUEST_CHANGES / NEEDS_DISCUSSION
Confidence: high | medium | low
Blockers: [list]
Non-blockers: [list]
```

## Hard-rule reminders

- Report confidence level for each finding.
- Distinguish "blocking" from "non-blocking" issues.
- Check if CI passed before calling coverage adequate.
- Destructive PRs (migrations, schema changes) require multi-agent consensus per CLAUDE.md.
