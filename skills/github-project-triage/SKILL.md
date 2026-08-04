---
name: github-project-triage
description: Triage open issues and PRs in a GitHub repository — label, prioritize, close stale, identify blocked items, and surface actionable work. Use when a repo's backlog needs organizing or a sprint planning pass is needed.
---

# github-project-triage — issue and PR backlog management

Performs a structured triage pass on a repo's open issues and PRs.

## When to use

- "このリポの issue をトリアージして"
- "古い PR を整理して"
- "バックログに何が溜まってるか確認して"
- Sprint planning prep

Do **not** use for:
- Closing issues without operator confirmation
- Reassigning issues to specific people without explicit instruction

## Triage sequence

```bash
# 1. Overview
gh issue list --repo <owner>/<repo> --state open --limit 100 --json number,title,labels,createdAt,updatedAt

# 2. Stale issues (no activity >30d)
gh issue list --repo <owner>/<repo> --state open \
  --json number,title,updatedAt \
  --jq '[.[] | select(.updatedAt < (now - 2592000 | strftime("%Y-%m-%dT%H:%M:%SZ")))]'

# 3. Open PRs
gh pr list --repo <owner>/<repo> --state open --json number,title,labels,isDraft,createdAt,reviewDecision

# 4. Blocked items (label: blocked or waiting)
gh issue list --repo <owner>/<repo> --label "blocked,waiting" --state open
```

## Output format

```markdown
## Triage Report: <repo>
Date: YYYY-MM-DD

### Action Required (operator confirms each)
- CLOSE: #<n> — <reason>
- LABEL: #<n> — add <label>
- PRIORITIZE: #<n> — <reason>

### Stale (no activity >30d)
- #<n>: <title> (last active: <date>)

### Blocked
- #<n>: <title> — waiting on: <description>
```

## Hard-rule reminders

- Present triage recommendations — do not execute without operator confirmation.
- Never close issues or PRs without operator approval.
- Label changes are lower risk but still confirm before applying.
