#!/usr/bin/env bash
# Tests memory-only/install.sh against a throwaway HOME: it installs the chosen
# files and only the three wanted skills, merges exactly one entry per installed
# hook into settings.json without touching other settings, and a second run
# changes nothing. Needs network once, to fetch the pinned claude-code-skills.
set -uo pipefail
FORK=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/memory-only-install.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" XDG_DATA_HOME="$TMP/data"
C="$HOME/.claude"
mkdir -p "$C"
PASS=0 FAIL=0
check() { if eval "$2"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $1"; fi; }
count() { jq --arg f "$1" --arg e "$2" '[.hooks[$e][]?.hooks[]? | select(.command | contains($f))] | length' "$C/settings.json" 2>/dev/null; }

# An existing settings.json: an old memory-lint entry, an empty group, another
# hook and an unrelated key, as a real one has.
cat > "$C/settings.json" <<'JSON'
{
  "model": "keep-me",
  "hooks": {
    "PostToolUse": [{"matcher": "Write|Edit|MultiEdit", "hooks": [{"type": "command", "command": "bash \"$HOME/.claude/hooks/memory-lint.sh\""}]}],
    "SessionStart": [{"hooks": []}, {"matcher": "^startup$", "hooks": [{"type": "command", "command": "other-hook.sh"}]}]
  }
}
JSON
chmod 600 "$C/settings.json"

out=$(umask 022 && bash "$FORK/memory-only/install.sh" 2>&1) || { echo "install failed:"; echo "$out"; exit 1; }
check "a private settings.json stays private" "[ \"\$(ls -l '$C/settings.json' | cut -c1-10)\" = '-rw-------' ]"
check "no temporary settings file left" "[ -z \"\$(ls '$C' | grep '^settings.json.new')\" ]"

for f in memory-index.sh memory-verify.sh memory-fix.sh memory-provenance.sh \
         hooks/lib.sh hooks/lib/memory-limits.sh hooks/lib/host.sh \
         hooks/memory-lint.sh hooks/memory-lint-stop.sh hooks/memory-session-start.sh hooks/plan-to-html.sh; do
  check "$f is installed and executable" "[ -x '$C/$f' ]"
done
check "rule installed" "[ -f '$C/rules/memory-writes.md' ]"
for s in memory-audit memory-archive skill-forge; do
  check "skill $s installed" "[ -f '$C/skills/$s/SKILL.md' ]"
done
check "skill-forge tools installed" "[ -x '$C/skills/skill-forge/bin/forge.py' ]"
check "skill-forge templates in the data dir" "[ -d '$XDG_DATA_HOME/skill-forge/templates' ]"
check "no template under skills/" "[ ! -e '$C/skills/skill-forge/templates' ]"
for s in pr-review slack-draft comms-hub harness-checkup; do
  check "skill $s not installed" "[ ! -e '$C/skills/$s' ]"
done
for g in audit.sh bash-guards.sh rm-guard.sh session-start.sh; do
  check "upstream hook $g not installed" "[ ! -e '$C/hooks/$g' ]"
done

check "one memory-lint entry"        "[ \"\$(count memory-lint.sh PostToolUse)\" = 1 ]"
check "one memory-lint-stop entry"   "[ \"\$(count memory-lint-stop.sh Stop)\" = 1 ]"
check "one memory-session-start"     "[ \"\$(count memory-session-start.sh SessionStart)\" = 1 ]"
check "one plan-to-html entry"       "[ \"\$(count plan-to-html.sh PreToolUse)\" = 1 ]"
check "plan-to-html is async on ExitPlanMode" \
  "[ \"\$(jq -c '[.hooks.PreToolUse[] | select(.matcher == \"ExitPlanMode\") | .hooks[0].async] ' '$C/settings.json')\" = '[true]' ]"
check "other hook kept"              "[ \"\$(count other-hook.sh SessionStart)\" = 1 ]"
check "unrelated key kept"           "[ \"\$(jq -r .model '$C/settings.json')\" = keep-me ]"
check "empty group removed"          "[ \"\$(jq '[.hooks[][] | select((.hooks | length) == 0)] | length' '$C/settings.json')\" = 0 ]"
check "one backup from the first run" "[ \"\$(ls '$C' | grep -c '^settings.json.bak-memory-only-')\" = 1 ]"

before=$(cksum < "$C/settings.json")
out=$(bash "$FORK/memory-only/install.sh" 2>&1) || { echo "second install failed:"; echo "$out"; exit 1; }
check "second run leaves settings.json as it was" "[ \"\$(cksum < '$C/settings.json')\" = '$before' ]"
check "second run makes no backup" "[ \"\$(ls '$C' | grep -c '^settings.json.bak-memory-only-')\" = 1 ]"

# The installed hooks load their libs and work as a pair: memory-lint records a
# memory with no index line, and memory-lint-stop reports it at Stop, once.
M="$C/projects/-tmp-store/memory"
mkdir -p "$M"
printf -- '---\nname: lone\ndescription: a fact\nmetadata:\n  type: reference\n---\nBody.\n' > "$M/lone.md"
printf -- '- [Other](other.md) — something else\n' > "$M/MEMORY.md"
jq -nc --arg f "$M/lone.md" '{tool_name:"Write",tool_input:{file_path:$f},session_id:"t1"}' \
  | bash "$C/hooks/memory-lint.sh" >/dev/null 2>&1
stop() { printf '{"session_id":"t1","stop_hook_active":false}' | bash "$C/hooks/memory-lint-stop.sh" 2>&1; }
first=$(stop) second=$(stop)
check "memory-lint-stop reports the missing index line" "printf '%s' \"\$first\" | grep -q 'no line in MEMORY.md points at lone.md'"
check "memory-lint-stop reports it once" "[ -z \"\$second\" ]"

echo "--- Results: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
