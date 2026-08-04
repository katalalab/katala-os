# Codex Ops Assets

This directory turns operational work into reusable agent assets.

## Files

- `asset-catalog.yaml`: source-of-truth catalog for reusable docs, scripts, runbooks, datasets, and backup evidence.

## Rules

- Catalog paths and purposes, not raw credentials or database contents.
- Prefer local relative paths inside this repo.
- For machine-local evidence, record the evidence path and verification command, not sensitive file content.
- Add a retention rule whenever the asset represents a backup or rollback surface.
