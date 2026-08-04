# Fleet known-hosts dry-run gate

This verifier is a strictly read-only preflight for one fleet node's ED25519 host key. It never provides an apply mode and never changes `known_hosts`, SSH configuration, credentials, or authentication state. The operator must supply an out-of-band `SHA256:` ED25519 fingerprint; no fingerprint is stored in this source tree.

## Run

```sh
PYTHONDONTWRITEBYTECODE=1 $HOME/.pyenv/versions/3.12.11/bin/python3 \
  codex-ops/scripts/fleet-known-hosts-gate.py \
  --node-id win-node-b \
  --expected-ed25519-sha256 SHA256:OUT_OF_BAND_VALUE
```

The canonical roster is `scripts/fleet-hosts.tsv`; override paths are available only for read-only test fixtures. The verifier accepts exactly one `online` node ID with a non-archive, non-no-SSH role and valid SSH alias, canonical DNS, and IPv4 address. It resolves only `/usr/bin/ssh-keyscan` and `/usr/bin/ssh-keygen`, checks their local executable type, and runs serial probes with exact arguments `ssh-keyscan -4 -q -T N -t ed25519 <target>`. Each command has a separate process deadline, bounded stdout/stderr capture, `DEVNULL` stdin, no shell, and explicit pipe cleanup.

It treats `ssh-keyscan` as unauthenticated transport data: both DNS and IPv4 scans must each produce one unique, structurally valid ED25519 key whose computed OpenSSH SHA256 fingerprint equals the operator's value. It then examines the existing known-hosts file only through bounded `ssh-keygen -F <alias|dns|ipv4> -f <file>` lookups, which support hashed records. A pass requires the expected key under the actual SSH alias; DNS and IPv4 matches are conflict checks and cannot substitute for alias registration. A return code of `1` counts as absent only when both bounded output streams are empty. Marker-bearing records such as `@revoked` and `@cert-authority` fail closed because they do not prove a direct usable host-key registration. It never invokes `ssh-keygen -h`.

Exit status: `0` is `pass` (the expected key is registered for the SSH alias with no ED25519 conflict); `2` is `actionRequired` (both scans match but alias registration is absent); `1` is `fail`. JSON output follows `fleet_known_hosts_gate.v1`, declares `mode: read-only` plus the matching `exitCode`, and contains only fixed states/counts plus a syntax-validated node ID and expected fingerprint. Invalid gate values are replaced with `invalid`, and parser failures emit only a fixed error; host keys, command data, supplied paths, stderr payloads, and exceptions are never emitted.

## Verify

```sh
PYTHONDONTWRITEBYTECODE=1 $HOME/.pyenv/versions/3.12.11/bin/python3 \
  codex-ops/scripts/test-fleet-known-hosts-gate.py
```

The synthetic unit test mocks every external command: it does not invoke SSH, `ssh-keyscan`, `ssh-keygen`, DNS, or a real `known_hosts` file. It covers exact argv/no shell, both canonical surfaces, alias-only pass semantics, key validation and conflicts, marker fail-closed behavior, timeout/output-cap failures, hashed lookup argv, lookup-error handling, roster validation, pipe cleanup, parser privacy, and the absence of an apply option.

## Evidence and review

- Retrieved: 2026-08-03 JST.
- Local controller: macOS OpenSSH_10.2p1.
- Sources: [ssh-keyscan(1)](https://man.openbsd.org/OpenBSD-7.4/ssh-keyscan.1), [ssh-keygen(1)](https://man.openbsd.org/OpenBSD-6.6/ssh-keygen.1), [ssh_config(5)](https://man.openbsd.org/OpenBSD-current/man/ssh_config), [ssh(1)](https://man.openbsd.org/OpenBSD-7.2/ssh.1).
- Decision: retain the host-key registration boundary with the operator; this tool can only produce a read-only evidence result.
- Risk: `ssh-keyscan` is vulnerable to MITM unless its result matches an independently obtained fingerprint; DNS or endpoint timeouts can fail the closed gate; OpenSSH behavior may drift after an upgrade.
- Refresh: 2026-09-03 JST, or immediately after an OpenSSH upgrade.

Rollback: remove `codex-ops/scripts/fleet-known-hosts-gate.py`, `codex-ops/scripts/test-fleet-known-hosts-gate.py`, and this runbook; revert only the `win-node-b` strict SSH section in `codex-ops/NEEDS_REVIEW.md`. No persistent machine state is created, so no restore command is required.
