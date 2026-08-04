#!/usr/bin/env bash
# fleet-optimize.sh — Katala OS Fleet Optimization Suite
#
# Tasks:
#   1. Apply row-level retention to Codex logs_2.sqlite if > 250 MiB (soft cap)
#   2. Run codex-home-gc.sh --apply
#   3. Sync ~/.gemini skills (now Antigravity state dir) to agent-skills-private
#   4. Active fleet optimization only

set -euo pipefail

TS=$(date +%Y%m%dT%H%M%S)
CODEX_HOME="${HOME}/.codex"
GEMINI_HOME="${HOME}/.gemini"
SKILLS_SRC="${HOME}/work/agent-skills-private/skills"

log() { printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >&2; }

# 1. Codex SQLite Rotation
if [[ -f "$CODEX_HOME/logs_2.sqlite" ]]; then
    SIZE=$(wc -c < "$CODEX_HOME/logs_2.sqlite" | tr -d ' ' | tr -d '\r')
    # 閾値と手段は批准済み AGENTS.MD の Maintenance 節に合わせる。ここが乖離していた:
    #   - 旧: 100 MiB 超で `mv logs_2.sqlite*` していた。これは (a) 100 MiB は到達不能な
    #     旧値(通常運用のログが既に超える水準)、(b) 稼働中の SQLite を
    #     -wal/-shm ごと移動するため Codex が書き込み中だと破損しうる、
    #     (c) baseline が要求する copy-first と write-lock yield を満たさない。
    #   - 新: soft cap 250 MiB。超過時は行単位 retention を使う。
    #     retention 側が quick_check 付きバックアップ・incremental_vacuum・
    #     write lock 時の yield・バックアップ2世代保持を行う。
    #     full VACUUM ではサイズは下がらない(実体は本物の行)ため rotation では解決しない。
    if [[ "$SIZE" -gt 262144000 ]]; then # 250 MiB (AGENTS.MD Maintenance)
        log "Codex SQLite over soft cap ($(ls -lh "$CODEX_HOME/logs_2.sqlite" | awk '{print $5}')): applying row-level retention"
        RETENTION="${HOME}/work/docs/scripts/codex-logs-retention.py"
        if [[ -x "$RETENTION" ]]; then
            python3 "$RETENTION" --keep-days 1 --apply || log "retention failed (non-fatal)"
        else
            log "retention script not found at $RETENTION — skipped (do NOT mv a live SQLite)"
        fi
    else
        log "Codex SQLite log is within the 250 MiB soft cap."
    fi
fi

# 2. Run GC Script
GC_SCRIPT="${HOME}/work/docs/scripts/codex-home-gc.sh"
if [[ -f "$GC_SCRIPT" ]]; then
    log "Running Codex Home GC..."
    bash "$GC_SCRIPT" --apply
else
    log "GC script not found at $GC_SCRIPT"
fi

# 3. Antigravity (~/.gemini) skill sync
if [[ -d "$SKILLS_SRC" ]]; then
    log "Syncing Antigravity (~/.gemini) skills..."
    mkdir -p "$GEMINI_HOME"
    if [[ -L "$GEMINI_HOME/skills" ]]; then
        log "Skills already symlinked."
    else
        if [[ -d "$GEMINI_HOME/skills" ]]; then
            log "Backing up existing skills directory..."
            mv "$GEMINI_HOME/skills" "$GEMINI_HOME/skills.bak-$TS"
        fi
        ln -sf "$SKILLS_SRC" "$GEMINI_HOME/skills"
        log "Skills symlinked to $SKILLS_SRC"
    fi
else
    log "Private skills source not found at $SKILLS_SRC"
fi

log "Optimization complete."
