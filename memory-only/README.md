# memory-only

This fork installs a small part of
[AdityaRon/claude-code-harness](https://github.com/AdityaRon/claude-code-harness)
into `~/.claude`. Upstream's `install.sh` installs everything, including its
guards. This folder installs only these items:

| Item | Source | Installed as |
|------|--------|--------------|
| memory-lint (checks each memory write) | `hooks/memory-lint.sh` | PostToolUse `Write\|Edit\|MultiEdit` |
| memory-lint-stop (reports a memory still missing its index line) | `hooks/memory-lint-stop.sh` | Stop |
| memory-session-start (keeps `MEMORY.md` in tier order) | `memory-only/hooks/memory-session-start.sh` | SessionStart |
| plan-to-html (opens a proposed plan as HTML) | `hooks/plan-to-html.sh` | PreToolUse `ExitPlanMode`, async |
| memory tools | `bin/memory-{index,verify,fix,provenance}.sh` | `~/.claude/` |
| hook libraries | `hooks/lib.sh`, `hooks/lib/` | `~/.claude/hooks/` |
| rule | `memory-only/rules/memory-writes.md` | `~/.claude/rules/` |
| skills | `memory-audit`, `memory-archive`, `skill-forge` from [claude-code-skills](https://github.com/AdityaRon/claude-code-skills) at the tag in `config/skills.pin` | `~/.claude/skills/` |

`pr-review`, `slack-draft`, `comms-hub` and `harness-checkup` are not installed.

`memory-session-start.sh` holds the memory sections of upstream's
`hooks/session-start.sh`. It is synced at upstream `5165ad3`. Its header lists
what it keeps and what it leaves out.

## Commands

```sh
just install        # install or reinstall; safe to re-run
just test           # our tests + upstream's tests for the installed files
just upstream-diff  # what upstream changed in the installed files
just sync           # merge upstream/main, then test
```

## Updating from upstream

1. Run `just upstream-diff`.
2. If `hooks/session-start.sh` changed, port the memory changes to
   `memory-only/hooks/memory-session-start.sh` by hand, and update its synced commit.
3. If a file that an installed file sources was added, add it to `install.sh`.
4. Run `just sync`, then `just install`.
