# Memory writes

- Write and edit memory files (`~/.claude/projects/*/memory/*.md`, including
  `MEMORY.md`) only with the Write or Edit tools. Never use a shell redirect,
  heredoc, `printf >>` or `sed -i` on them.
  **Why:** only the file tools get the CLI's `modified` stamp and trigger
  memory-lint, which checks each memory when it is written.
- When memory-lint reports a finding, fix it in the same turn.

Scope: every session on this machine. Source: claude-code-harness
`rules/environment.md`; installed by `memory-only/install.sh` in
seanGSISG/claude-code-harness.
