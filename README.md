# claude-code-harness: memory-only fork

This is a fork of [AdityaRon/claude-code-harness](https://github.com/AdityaRon/claude-code-harness).
Upstream installs a full set of Bash guards and session hooks. This fork
installs only the memory features, the plan viewer, and three skills into
`~/.claude`. It installs no guards.

All upstream code stays in the repo, unedited, so upstream changes merge
cleanly. Our changes are in `memory-only/`, this README, the `justfile`, and
the one CI workflow. Upstream's own workflows are deleted here.

## What it installs

| Item | Runs | What it does |
|------|------|--------------|
| `memory-lint` | After each `Write`, `Edit` or `MultiEdit` | Checks a memory file when it is written. Reports problems to Claude in the same turn. |
| `memory-lint-stop` | At the end of each turn | Reports a memory that still has no line in `MEMORY.md`. |
| `memory-session-start` | At session start | Keeps `MEMORY.md` in tier order when the index is near its limit. |
| `plan-to-html` | Before `ExitPlanMode` (async) | Saves the proposed plan as an HTML page and opens it in the browser. |
| Memory tools | When you or a skill run them | `memory-index.sh`, `memory-verify.sh`, `memory-fix.sh`, `memory-provenance.sh` in `~/.claude/`. |
| Rule | Every session | `~/.claude/rules/memory-writes.md`: write memory files only with the Write or Edit tools. |
| Skills | When Claude picks them | `memory-audit`, `memory-archive` and `skill-forge`, from [claude-code-skills](https://github.com/AdityaRon/claude-code-skills) at the tag in `config/skills.pin`. |

These parts are **not** installed: the Bash guards, `audit`, upstream's full
`session-start`, the other upstream hooks, and the skills `pr-review`,
`slack-draft`, `comms-hub` and `harness-checkup`.

## How the hooks work

**memory-lint** runs only on files under `*/memory/*.md`. It never blocks a
write and never edits a file. It writes its findings to stderr and exits with
code 2, so Claude reads them. Claude Code shows this as a hook error.

- For a memory file, it checks:
  - the frontmatter: `name` matches the file name, `type` is one of `user`,
    `feedback`, `project` or `reference`, and `description` exists;
  - `metadata.modified` and `metadata.originSessionId`;
  - a description or index line that states changing facts, such as
    "3 PRs open";
  - a claim of work in progress with no `verify:` block;
  - `[[links]]` that do not resolve;
  - an index line that is too long, or in the wrong type section.
- For `MEMORY.md`, it checks the 200-line and 25,000-byte limits, `feedback`
  entries past the cut, and lines fused by an append without a newline.
- A memory with no index line is not an error at once. It is recorded, and
  `memory-lint-stop` reports it at the end of the turn if the line is still
  missing.
- It also checks handoff files under `*/trackers/*.md`. Set
  `CLAUDE_TRACKER_LINT=off` in the `env` of `settings.json` to stop this.

**memory-session-start** runs `memory-index.sh` on the store of the session's
start folder. It runs only when all of these are true:

- the index has 180 or more lines, or 20,000 or more bytes;
- the index changed since the last run;
- Claude Code's own memory consolidation is not running.

The reorder only moves lines: feedback, then reference, then project, with the
newest first. It adds, removes and edits nothing. Once a day, the hook also
deletes `memory-lint` pending lists that are more than a day old.

**plan-to-html** writes the plan to `~/.claude/plans-html/plan-<time>.html`
and opens it with `open` or `xdg-open`. It runs async, so it never delays the
approval prompt. Set `CLAUDE_PLAN_HTML_NO_OPEN=1` to save the page without
opening it. On WSL, `xdg-open` uses the Linux default browser. To use the
Windows browser, run `xdg-settings set default-web-browser wslview.desktop`.

**The memory tools:**

- `memory-index.sh --store <slug> [--write]` checks or restores tier order.
- `memory-verify.sh` checks memory claims against GitHub (with `gh`) and lists
  Jira claims to check. It is read-only.
- `memory-fix.sh` repairs the mechanical defects that `memory-verify.sh` reports.
- `memory-provenance.sh` shows which session wrote each memory.

The design and its measurements are in [docs/memory.md](docs/memory.md).

## Install

You need `bash`, `jq` and `git`. `skill-forge` also needs Python 3.10 or later
with a TOML reader: `tomllib` is built in from 3.11, and 3.10 needs the `tomli`
package. `memory-verify.sh` needs `gh` for GitHub checks.

```sh
git clone https://github.com/seanGSISG/claude-code-harness ~/projects/claude-code-harness
cd ~/projects/claude-code-harness
just install    # or: bash memory-only/install.sh
```

The install does these steps:

1. It copies the hooks, the hook libraries, the tools and the rule into `~/.claude`.
2. It fetches the pinned `claude-code-skills` release into
   `~/.cache/claude-code-skills` and checks its commit against
   `config/skills.pin`. Then it copies only the three skills.
   `skill-forge`'s templates go to `~/.local/share/skill-forge/templates`.
3. It merges one entry for each hook into `~/.claude/settings.json`. It
   replaces older entries for the same hooks and keeps all other settings.
   Before it changes the file, it saves a copy as
   `settings.json.bak-memory-only-<time>`.

You can run the install again at any time. A second run changes nothing.
New Claude Code sessions use the hooks; running sessions do not.

Do not run upstream's `install.sh`. It installs every guard.

## Commands

| Command | What it does |
|---------|--------------|
| `just install` | Installs or reinstalls everything above. |
| `just test` | Runs our tests and upstream's tests for every installed file. |
| `just upstream-diff` | Fetches upstream and lists what changed in the installed files. |
| `just sync` | Merges `upstream/main` into this branch, then runs `just test`. |

## Update from upstream

1. Run `just upstream-diff`.
2. If `hooks/session-start.sh` changed, port its memory changes by hand to
   `memory-only/hooks/memory-session-start.sh`, and update the synced commit
   in that file's header (now `5165ad3`).
3. If an installed file now loads a new file, add that file to
   `memory-only/install.sh`.
4. Run `just sync`. It keeps our README when upstream changes theirs, and
   keeps upstream's workflows deleted.
5. Run `just install`.

To install a newer skills release, update `config/skills.pin` (upstream does
this) and run `just install`.

## Repo layout

| Path | Owner |
|------|-------|
| `memory-only/install.sh` | Ours: the installer. |
| `memory-only/hooks/memory-session-start.sh` | Ours: the memory parts of upstream's `hooks/session-start.sh`. |
| `memory-only/rules/memory-writes.md` | Ours: the one rule we install. |
| `memory-only/tests/` | Ours: tests for the installer and the session-start hook. |
| `justfile`, `AGENTS.md`, `CLAUDE.md`, `README.md`, `.gitattributes` | Ours. |
| `.github/workflows/memory-only.yml` | Ours: the only CI. It runs our tests and upstream's tests for the installed files. |
| Everything else | Upstream, unedited. Upstream's workflows (`ci`, `claude`, `guard-props-daily`, `release`, `upstream-drift`) are deleted. |

Report bugs in upstream code to upstream, and fix them there.

## License

MIT, in [LICENSE](LICENSE). The harness and the skills are by Aditya Samalla
([AdityaRon](https://github.com/AdityaRon)).
