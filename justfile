# Memory-only install of claude-code-harness (fork seanGSISG/claude-code-harness).
# Upstream files stay unedited; our additions live in memory-only/.

# Upstream files that install.sh copies, or that memory-session-start.sh is cut from.
installed := "bin/memory-index.sh bin/memory-verify.sh bin/memory-fix.sh bin/memory-provenance.sh hooks/lib.sh hooks/lib hooks/memory-lint.sh hooks/memory-lint-stop.sh hooks/plan-to-html.sh hooks/session-start.sh config/skills.pin"

# List the recipes
default:
    @just --list

# Install the memory hooks, plan-to-html, memory tools and three skills into ~/.claude
install:
    bash memory-only/install.sh

# Run our tests and upstream's tests for every installed file
test:
    bash memory-only/tests/memory-session-start.test.sh
    bash memory-only/tests/install.test.sh
    for t in memory-lint memory-index memory-verify memory-fix memory-provenance plan-to-html; do bash tests/$t.test.sh || exit 1; done

# Fetch upstream and list what changed in the installed files since our last merge
upstream-diff:
    git fetch -q upstream
    git diff --stat HEAD upstream/main -- {{installed}}

# Merge upstream main into this branch, keeping our README and our workflow deletions, then test
sync:
    #!/usr/bin/env bash
    set -euo pipefail
    git fetch -q upstream
    git config merge.ours.driver true   # .gitattributes: README.md merge=ours
    before=$(git rev-parse HEAD)
    if ! git merge --no-edit upstream/main; then
      # An upstream change to a workflow we deleted is a modify/delete conflict: keep it deleted.
      git rm -q --ignore-unmatch .github/workflows/{ci,claude,guard-props-daily,release,upstream-drift}.yml
      if [ -n "$(git diff --name-only --diff-filter=U)" ]; then
        echo "sync: resolve the conflicts above, commit, then run just test" >&2; exit 1
      fi
      git commit --no-edit -q
    fi
    added=$(git diff --name-only --diff-filter=A "$before" HEAD -- .github/workflows)
    [ -z "$added" ] || echo "sync: upstream added workflows; delete them if we do not need them: $added"
    just test
