# Contributing

## Fork first, and expect to keep the fork

This repository publishes the **shape** of an operating discipline, not a configurable
framework. The intended use is: fork it, rewrite `AGENTS.MD` and the policy documents for
your own environment, and diverge. Most of what makes it useful is exactly what you should
change.

That means the most valuable contribution is usually **not** a pull request. If a rule here
turned out to be wrong in your environment, an issue explaining what broke is worth more than
a patch that makes the rule configurable.

## What pull requests are welcome

- Bug fixes in the shipped scripts and hooks — a broken code path, an unsafe expansion, a
  wrong default, a platform assumption that fails.
- Portability fixes, especially Linux and Windows: this was built against macOS and
  Windows + WSL2 and there are certainly assumptions baked in.
- Documentation that is factually wrong or describes a step that does not work.
- Translations of the remaining Japanese inline comments into English. Several scripts and
  hooks still carry their original Japanese rationale comments; they are accurate and worth
  keeping, but the repository reads as English. Translate the meaning, not just the words —
  if a comment explains *why* a workaround exists, that reasoning is the part to preserve.

## What pull requests will probably be declined

- Adding configuration knobs to make a policy choice adjustable. Fork instead.
- New runbooks or skills for environments the maintainer does not run and cannot verify.
- Changes to `CONSTITUTION.md`. It is deliberately narrow and hash-locked; changing it in a
  fork is correct, changing it upstream needs a strong argument.

## Two mechanical rules

**1. Never commit instance data.** The CI gate `scripts/check-no-instance-data.sh` rejects real
hostnames, private and Tailscale-range addresses, home paths containing an account name,
credential shapes, account identifiers, and "observed X on DATE" narratives. Run it before
pushing:

```bash
./scripts/check-no-instance-data.sh
```

The gate cannot see semantic leaks. If your change adds a measurement, an incident story, or a
tool inventory, ask whether it describes *a* system or *your* system, and rewrite it as the
former.

**2. Hash-locked files change with their lock.** Editing `CONSTITUTION.md` or
`AGENTS-COMMUNICATION.md` requires updating the recorded hash in `manifest.lock.json` in the
same commit. `./scripts/verify.sh` fails until you do — that is the mechanism that stops an
agent from quietly rewriting the rules it operates under, so do not work around it.

## Local checks

```bash
./scripts/verify.sh                     # hash-lock + skill validation
./scripts/check-no-instance-data.sh     # publication gate
```

Both run in CI on every pull request. `codex-ops/scripts/validate-learning-data.sh` needs Ruby
and is not wired into CI.

## Repository settings (maintainer note)

Branch protection on `main`, secret scanning with push protection, and Dependabot alerts should
be enabled in repository settings. Workflows run on GitHub-hosted runners only — never point CI
at a self-hosted runner on a public repository, since fork pull requests would then execute on
that machine.

## License

MIT. By opening a pull request you agree your contribution is published under it.
