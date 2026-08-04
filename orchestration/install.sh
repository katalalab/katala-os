#!/usr/bin/env bash
# install.sh — このノードに「Claudeリードのマルチエンジン・オーケストレーション」を導入する。
# 冪等。再実行安全。macOS / Linux (および git-bash/WSL) 用。
#
#   1. bin/agent-dispatch, bin/agent-handoff, agent-review-after-change を ~/bin に symlink (PATH前提)
#   2. agents/*.md を ~/.claude/agents/ にコピー (Task委譲サブエージェント)
#   3. hooks/orchestration-context を ~/.claude/hooks/ にコピー
#   4. ~/.claude/settings.json の SessionStart に hook を冪等追加 (バックアップ+JSON検証付き)
#
# skill(agent-orchestration) は agent-skills-private 経由で別途同期されるためここでは扱わない。
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
mkdir -p "$HOME/bin" "$CLAUDE_DIR/agents" "$CLAUDE_DIR/hooks"

echo "orchestration install (source: $DIR)"

# 1. bin
for b in agent-dispatch agent-handoff agent-review-after-change; do
  chmod +x "$DIR/bin/$b"
  ln -sf "$DIR/bin/$b" "$HOME/bin/$b"
  echo "  link  ~/bin/$b -> $DIR/bin/$b"
done

# 2. agents
for a in "$DIR/agents/"*.md; do
  cp "$a" "$CLAUDE_DIR/agents/"
  echo "  copy  ~/.claude/agents/$(basename "$a")"
done

# 3. hook
cp "$DIR/hooks/orchestration-context" "$CLAUDE_DIR/hooks/orchestration-context"
chmod +x "$CLAUDE_DIR/hooks/orchestration-context"
echo "  copy  ~/.claude/hooks/orchestration-context"

# 4. settings.json に SessionStart hook を冪等追加 (python3 で安全に)
SETTINGS="$CLAUDE_DIR/settings.json"
if command -v python3 >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
  ts="$(date +%Y%m%d-%H%M%S)"
  cp "$SETTINGS" "$SETTINGS.bak-$ts-orchestration"
  python3 - "$SETTINGS" <<'PY'
import json, sys
p = sys.argv[1]
with open(p) as f: cfg = json.load(f)
HOOK = "~/.claude/hooks/orchestration-context"
hooks = cfg.setdefault("hooks", {})
ss = hooks.setdefault("SessionStart", [])
def has_hook(arr):
    for entry in arr:
        for h in entry.get("hooks", []):
            if h.get("command","") == HOOK: return True
    return False
if not has_hook(ss):
    # startup|resume の既存エントリに相乗り、無ければ新規
    target = next((e for e in ss if e.get("matcher")=="startup|resume"), None)
    if target is None:
        target = {"matcher":"startup|resume","hooks":[]}
        ss.append(target)
    target.setdefault("hooks", []).append({"type":"command","command":HOOK})
    with open(p,"w") as f: json.dump(cfg, f, indent=2, ensure_ascii=False)
    print("  patch ~/.claude/settings.json (SessionStart hook added)")
else:
    print("  ok    settings.json already has orchestration hook")
PY
  python3 -c "import json;json.load(open('$SETTINGS'))" || { echo "  ERROR settings.json invalid, restoring"; cp "$SETTINGS.bak-$ts-orchestration" "$SETTINGS"; exit 1; }
else
  echo "  skip  settings.json patch (python3 or settings.json missing) — add hook manually"
fi

# Retention: keep the newest five orchestration settings backups.
if [ -d "$CLAUDE_DIR" ]; then
  backup_index=0
  while IFS= read -r backup; do
    backup_index=$((backup_index + 1))
    if [ "$backup_index" -gt 5 ]; then
      rm -f "$backup"
      echo "  prune ~/.claude/$(basename "$backup")"
    fi
  done < <(ls -1t "$CLAUDE_DIR"/settings.json.bak-*-orchestration 2>/dev/null || true)
fi

echo
echo "Done. Restart your Claude session to load the new subagents and hook."
echo "Available engines on this node:"
for c in codex cursor-agent opencode agy; do printf "  %-13s " "$c"; command -v "$c" >/dev/null 2>&1 && echo present || echo absent; done
