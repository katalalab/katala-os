# Runbook: Learning Data Assetization

Use this when turning operational experience into reusable Codex Ops data.

## Boundary

Learning data records patterns, decisions, evidence requirements, and safe file paths. It does not copy raw logs, database rows, credentials, cookies, tokens, shell snapshots, or private key material.

## Required Shape

For JSONL examples, include:

```text
id
domain
task_type
locale
trigger
must_do
must_not_do
evidence
success_criteria
rubric
```

For antipattern cases, include:

```text
id
domain
severity
trigger_signals
antipattern
preferred_behavior
forbidden_behavior
evidence_required
```

## Validate

```sh
codex-ops/scripts/validate-learning-data.sh
```

## Publish Boundary

Before committing or publishing:

- run the validator,
- run a secret scan on the publication boundary,
- keep machine-local evidence as paths or summaries only,
- block publication if the secret scan cannot run for backup-like material.
