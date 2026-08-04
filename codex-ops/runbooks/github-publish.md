# Runbook: GitHub Publish

## Preflight

```sh
git status --short
git remote -v
ssh_output=$(ssh -T git@github.com 2>&1 || true)
printf '%s\n' "$ssh_output" | rg 'successfully authenticated|Hi .*!'
gh auth status
gh repo view <owner>/<repo> --json nameWithOwner,visibility,viewerPermission
git ls-remote --heads origin
```

GitHub SSH authentication normally prints a success greeting but may exit non-zero because GitHub does not provide shell access. Treat the greeting text, not the raw exit code, as the pass condition.

## Sensitive or Backup-Like Repos

Required:

- private repository unless user explicitly requests public,
- secret scan,
- publication boundary,
- history risk review.

If history is risky, publish a tracked-tree snapshot instead of full history:

```sh
git archive HEAD | tar -x -C <snapshot-dir>
```

## Completion

Completion requires:

- local status clean or explained,
- remote branch exists and points to expected commit,
- push permissions verified,
- secret scan result captured when needed,
- remote cleanup attempted or blocked reason documented.
