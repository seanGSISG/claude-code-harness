#!/usr/bin/env bash
# Tests memory-only/hooks/memory-session-start.sh in a throwaway HOME laid out as
# install.sh lays out ~/.claude: it reorders an out-of-order index under
# pressure, leaves a small index alone, prints nothing, and prunes memory-lint
# pending lists a day old while keeping today's.
set -uo pipefail
FORK=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/memory-only-ss.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
C="$HOME/.claude"
mkdir -p "$C/hooks/lib" "$C/state/sessions"
cp -p "$FORK/hooks/lib.sh" "$C/hooks/"
cp -p "$FORK"/hooks/lib/*.sh "$C/hooks/lib/"
cp -p "$FORK/memory-only/hooks/memory-session-start.sh" "$C/hooks/"
cp -p "$FORK/bin/memory-index.sh" "$C/"
PASS=0 FAIL=0
check() { if eval "$2"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $1"; fi; }

# store DIR N: N project memories, then one feedback memory appended last, the
# way the memory writer leaves a store: out of tier order.
store() {
  local m="$C/projects/$1/memory" i
  mkdir -p "$m"
  : > "$m/MEMORY.md"
  for ((i = 1; i <= $2; i++)); do
    printf -- '---\nname: project_%s\ndescription: work %s\nmetadata:\n  type: project\n---\nBody.\n' "$i" "$i" > "$m/project_$i.md"
    printf -- '- [Work %s](project_%s.md) — work %s\n' "$i" "$i" "$i" >> "$m/MEMORY.md"
  done
  printf -- '---\nname: feedback_rule\ndescription: a rule\nmetadata:\n  type: feedback\n---\nBody.\n' > "$m/feedback_rule.md"
  printf -- '- [Rule](feedback_rule.md) — a rule\n' >> "$m/MEMORY.md"
}
run() {  # LAUNCH_DIR
  jq -nc --arg d "$1" '{source:"startup",session_id:"s1",cwd:$d}' | bash "$C/hooks/memory-session-start.sh" 2>&1
}
rule_line() { grep -n 'feedback_rule.md' "$C/projects/$1/memory/MEMORY.md" | cut -d: -f1; }

# Under pressure (180+ lines): reordered, the feedback entry moved to the top.
store -work-big 185
out=$(run /work/big)
check "silent under pressure" "[ -z \"\$out\" ]"
check "feedback entry moved above the project entries" "[ \"\$(rule_line -work-big)\" -lt 5 ]"
check "no entry lost" "[ \"\$(grep -c '^- \\[' '$C/projects/-work-big/memory/MEMORY.md')\" = 186 ]"

# No pressure: left exactly as written.
store -work-small 5
before=$(cksum < "$C/projects/-work-small/memory/MEMORY.md")
run /work/small >/dev/null
check "small index left alone" "[ \"\$(cksum < '$C/projects/-work-small/memory/MEMORY.md')\" = '$before' ]"

# No store at all: no error, no output.
out=$(run /work/none)
check "no store: silent" "[ -z \"\$out\" ]"

# Pending lists: a day-old one is pruned, today's is kept.
P="$C/state/sessions/lint-pending"
mkdir -p "$P"
echo "1 /x.md" > "$P/old-session" && touch -d '2 days ago' "$P/old-session"
echo "1 /y.md" > "$P/new-session"
run /work/none >/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -e "$P/old-session" ] || break; sleep 0.2; done
check "day-old pending list pruned" "[ ! -e '$P/old-session' ]"
check "today's pending list kept" "[ -e '$P/new-session' ]"

echo "--- Results: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
