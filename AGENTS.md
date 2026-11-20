# claude-code-harness (memory-only fork)

This is seanGSISG's fork of AdityaRon/claude-code-harness. We install only the
memory features and plan-to-html, through `memory-only/install.sh`. Read
`README.md` first.

- Do not edit upstream files (everything outside `memory-only/`, `justfile`,
  `AGENTS.md`, `CLAUDE.md`, `README.md`, `.gitattributes` and
  `.github/workflows/memory-only.yml`). Change behavior in `memory-only/`, so
  that `just sync` merges upstream cleanly.
- Upstream's workflows are deleted on purpose; `just sync` keeps them deleted.
- Fix upstream bugs upstream: open an issue or PR on AdityaRon/claude-code-harness.
- Do not run upstream's `install.sh`: it installs every guard.
- Remotes: `origin` is the fork, `upstream` is AdityaRon/claude-code-harness.
- Before a push, run `just test`.
