# Codex Ops Antipatterns

These are failure modes to prevent through hooks, evals, and runbooks.

Machine-readable cases live in `evals/antipattern-cases.yaml`.

| Antipattern | Cause | Detection Signal | Guardrail |
|---|---|---|---|
| Treating backup start as backup completion | copy and cloud upload are separate | `rsync` success only, no upload evidence | require final artifact verification |
| Using `rsync -E` as default for Drive paths | AppleDouble/xattr handling can fail | `copyfile` or AppleDouble errors | fallback to plain `rsync -a` for Drive |
| Chasing volatile backup diffs forever | live apps mutate logs, Photos metadata, LevelDB, FileProvider temp files | repeated `rsync -an` differences in volatile paths | classify stable vs volatile diffs |
| Judging Drive upload by folder state | folder status is too coarse | folder visible but files still uploading | evaluate representative files or tarball |
| Treating GitHub SSH auth as repo push permission | SSH greeting only proves identity | `Hi user!` but push denied | check `gh auth status` and repo permissions |
| Calling local Git clean enough for GitHub completion | remote branches and permissions still matter | local clean, remote stale | verify remote state and push rights |
| Publishing backup history directly | old commits/stashes can contain secrets | gitleaks history findings | private repo plus snapshot boundary |
| Scanning entire backup tree blindly | too slow and noisy | vendored docs, evidence logs, false positives | scan the publish boundary |
| Broad gitleaks allowlist | hides real findings | generic regex allowlist | narrow, documented false-positive rules |
| Assuming 1Password SSH keys are usable because listed | signing still needs approval/unlock | `agent refused operation` | prove one end-to-end SSH login |
| Assuming Tailscale SSH is enabled | local GUI may have `RunSSH=false` | `tailscale set --ssh=true` fails | use OpenSSH over MagicDNS |
| Bulk SSH before network classification | offline, closed, auth failures blur together | mixed timeouts and denials | status -> TCP -> `ssh -G` -> auth |
| Treating Tailscale `check-required` as auto-fixable | user approval required | approval URL | report blocker and continue other work |
| Declaring fleet-wide SSH done in aggregate | hosts fail independently | some hosts offline or closed | host matrix with reason per host |
| Guessing SSH config expansion | aliases and IdentityAgent can differ | wrong host or key | use `ssh -G` |
| Choosing GitHub repo by name only | purpose and permissions can differ | similar repos | inspect README and permissions |
| Touching old stash casually | may contain sensitive changes | many old stashes | leave alone unless explicitly requested |
| Assuming `/tmp` is healthy | local symlink/env may be broken | temp creation failure | use `mktemp -d` and fallback |
| Compiling shell as Python | broad verifier misclassifies files | `.sh` passed to `py_compile` | extension-specific lint |
| Leaving tmux monitor running after completion | monitor lifecycle not tied to task | stale tmux sessions | stop monitor and delete heartbeat automation |

## Immediate P0 Guardrails

1. Backup completion must include artifact-level verification.
2. GitHub publication must include push permission and remote state.
3. Tailscale/SSH work must classify `RunSSH=false`, offline, closed, auth, and approval-required.
4. Backup-like GitHub publication must be private and secret-scanned.
5. tmux long-running jobs must have logs and final report.
6. Learning-data assetization must stay metadata-only and exclude raw secrets, DB rows, and unredacted logs.
