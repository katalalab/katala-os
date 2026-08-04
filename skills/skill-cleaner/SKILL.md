---
name: skill-cleaner
description: Audit and clean up the ~/.claude/skills/ directory — detect broken symlinks, stale .bak directories, duplicate skills, and symlinks pointing to deleted repos. Use when skills are accumulating clutter or broken links are causing load errors.
---

# skill-cleaner — ~/.claude/skills/ maintenance

Audits the skill directory and reports what to clean. Never deletes without operator confirmation.

## When to use

- "スキルディレクトリを整理して"
- "壊れたスキルリンクがある、確認して"
- "skills の .bak ディレクトリが溜まってる"
- After skill migrations or repo moves

Do **not** use for:
- Deleting active, working skills
- Modifying skill content (use the skill's own update process)

## Audit steps

```bash
# 1. Count total skills and symlinks
ls ~/.claude/skills/ | wc -l

# 2. Detect broken symlinks
find ~/.claude/skills/ -maxdepth 1 -type l | while read l; do
  [ ! -e "$l" ] && echo "BROKEN: $l -> $(readlink $l)"
done

# 3. List .bak directories (stale backups)
ls -d ~/.claude/skills/*.bak-* 2>/dev/null | wc -l
ls -d ~/.claude/skills/*.bak-* 2>/dev/null | head -10

# 4. Detect duplicate skills (symlinks pointing to same target)
find ~/.claude/skills/ -maxdepth 1 -type l -exec readlink {} \; | sort | uniq -d
```

## Cleanup (operator confirms each step)

```bash
# Remove broken symlinks
# !! Requires operator explicit confirmation for each batch !!
find ~/.claude/skills/ -maxdepth 1 -type l ! -follow | xargs rm

# Remove stale .bak directories (>7 days)
find ~/.claude/skills/ -maxdepth 1 -name "*.bak-*" -type d -mtime +7 -exec rm -rf {} +
```

## Hard-rule reminders

- Always audit first (read-only pass), then report findings before any deletion.
- Auto mode blocks self-modification of `~/.claude/skills/` — the operator must run cleanup commands directly or add explicit Bash permissions.
- Deletions are irreversible for non-git directories. Confirm targets before proceeding.
