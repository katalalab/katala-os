# Runbook: tailscaled Log Size Gate

`scripts/tailscaled-log-size-gate.py` is a local, stdout-only metadata gate for one absolute log path. It uses only `os.lstat`: it never opens or reads log contents, and it does not follow a symlink at the final path component; ordinary parent-directory path resolution still applies. It never writes or persists artifacts, invokes subprocesses, uses the network, runs `sudo`, calls `launchctl` or `newsyslog`, sends signals, restarts services, or truncates files.

The schema is `tailscaled_log_size_gate.v1`. Output contains only `schema`, `state`, `issues`, and `file`; `file` is limited to `exists`, `regular`, `symlink`, `sizeBytes`, and `inode`. It never emits the supplied path, ownership, group, mode, contents, exceptions, or command data.

## Safe now

Run the read-only gate manually against an operator-selected absolute path:

```sh
PYTHONDONTWRITEBYTECODE=1 $HOME/.pyenv/versions/3.12.11/bin/python3 \
  codex-ops/scripts/tailscaled-log-size-gate.py \
  --path /absolute/operator-selected/tailscaled.log \
  --warn-bytes 134217728 --critical-bytes 268435456
```

Exit `0` means `ok`; `2` means `degraded` from `SIZE_WARNING` or `INODE_CHANGED`; `1` means fail-closed for invalid arguments, missing/unreadable/nonregular/symlink files, or `SIZE_CRITICAL`. The warn threshold is inclusive; the larger critical threshold is inclusive. An optional positive `--expected-inode` detects rotation/replacement and combines with other issues in sorted unique order.

Do not schedule this gate or perform rotation, `SIGHUP`, restart, truncate, `newsyslog`, or launchd changes in this slice. An unrotated `tailscaled` log can grow to hundreds of megabytes, which is what this gate exists to notice; it records metadata only and never reads raw content.

## Evidence and limitations

Official evidence retrieved 2026-08-03: [Tailscale `v1.98.8` signal handling](https://github.com/tailscale/tailscale/blob/v1.98.8/cmd/tailscaled/tailscaled.go#L482-L505), [Apple `newsyslog` close/reopen behavior](https://github.com/apple-oss-distributions/syslog/blob/syslog-406/newsyslog/newsyslog.8#L173-L214), and the [launchd plist stdout/stderr contract](https://github.com/apple-oss-distributions/launchd/blob/launchd-842.92.1/man/launchd.plist.5#L274-L282). Any remediation that relies on those controls needs a separately reviewed, operator-approved change plan. This gate is subject to normal TOCTOU limitations: a file may rotate, grow, or be replaced after `lstat` returns. An inode expectation reports that replacement but cannot make the stat atomic with a future remediation.

## Verify

```sh
PYTHONDONTWRITEBYTECODE=1 $HOME/.pyenv/versions/3.12.11/bin/python3 \
  codex-ops/scripts/test-tailscaled-log-size-gate.py
```

Rollback: delete only these three new gate files. They create no state, artifacts, schedules, service changes, or log changes.
