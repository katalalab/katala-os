---
name: github-author-context
description: Build a contributor profile for a GitHub user — repos, contribution patterns, languages, notable PRs, activity timeline. Use when evaluating a contributor, understanding a codebase owner, or researching an open-source author.
---

# github-author-context — GitHub contributor profile

Builds a factual profile from public GitHub data via `gh` CLI.

## When to use

- "このリポの作者について調べて"
- "この PR の作者はどんな人？"
- "コントリビューターのバックグラウンドを調べて"

Do **not** use for:
- Internal/private user lookups (no access to private data)
- Anything that could constitute surveillance or PII extraction

## Data sources

```bash
# Public profile
gh api users/<username>

# Recent repos
gh api users/<username>/repos --jq '[.[] | {name, language, stars: .stargazers_count, updated: .updated_at}] | sort_by(.updated) | reverse | .[0:10]'

# Recent public activity
gh api users/<username>/events/public --jq '[.[] | {type, repo: .repo.name, created: .created_at}] | .[0:20]'

# PRs to a specific repo
gh pr list --repo <owner>/<repo> --author <username> --state all --limit 20
```

## Output format

```markdown
## Author: <username>
- Name: ...
- Bio: ...
- Company: ...
- Location: ...
- Joined: ...
- Top languages: ...
- Notable repos: ...
- Activity pattern: ...
```

## Hard-rule reminders

- Use only public GitHub API data.
- Do not include email addresses, personal details, or inferred PII in outputs.
- Frame analysis as observable patterns, not personal judgments.
