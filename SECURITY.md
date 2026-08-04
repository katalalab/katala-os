# Security

## What this repository ships

Shell scripts, Node hooks, and PowerShell scripts that **run on your machine and
change files in your home directory**. Specifically:

- `scripts/bootstrap.sh` / `bootstrap.ps1` replace `~/CLAUDE.md`, `~/AGENTS.md`, and
  `~/GEMINI.md` with symlinks (backing up whatever was there first).
- `hooks/` installs `PreToolUse` hooks into `~/.claude/settings.json` and a `pre-commit`
  hook into a repository.
- `orchestration/` installs `agent-dispatch`, which spawns other coding agents as
  subprocesses.

Read a script before you run it. This is not a package with a maintained security
boundary; it is one operator's working setup, published because the patterns are
reusable.

## What the safety valves are and are not

The `PreToolUse` valves are **advisory and non-blocking by design**. They warn, back up
state markers, and surface risky commands. They do **not** sandbox an agent and cannot
stop a determined or confused one. Do not treat their presence as containment.

`agent-dispatch --read-only` asks the downstream agent for a read-only sandbox. On
Windows it also filters PowerShell 7 out of `PATH`, because the Codex sandbox cannot
start pwsh under a restricted token; the code documents a known limitation where an
MSI-installed pwsh is found anyway. When that happens the downstream agent fails to
start — it does not silently run with write access — but you should verify the mode
your agent actually entered rather than assuming.

## Reporting a vulnerability

Open a **draft security advisory** on this repository
(Security → Advisories → New draft advisory), or if that is unavailable, open a normal
issue that describes the class of problem without a working exploit and ask for a
private channel.

Please report anything that would cause a reader following the documentation to lose
data, expose a secret, or grant an agent more authority than the documentation implies.
That last category is the one that matters most here.

There is no service, no deployed infrastructure, and no user data in scope — only the
code you would run locally.

## No embargo commitments

This is maintained by one person as time allows. There is no guaranteed response time
and no CVE process. Fixes land as normal commits.
