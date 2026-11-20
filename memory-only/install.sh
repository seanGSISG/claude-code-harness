#!/usr/bin/env bash
# Installs a chosen part of claude-code-harness into ~/.claude, and nothing else:
#   - the memory hooks: memory-lint (on each memory write), memory-lint-stop (at
#     Stop) and memory-session-start (index reorder at session start);
#   - plan-to-html (renders a proposed plan as HTML and opens it);
#   - the memory tools (memory-index, -verify, -fix, -provenance) and the hook
#     libraries they all load;
#   - one rule (rules/memory-writes.md);
#   - the memory-audit, memory-archive and skill-forge skills, from the
#     claude-code-skills release that config/skills.pin names.
# No guard, audit or other upstream hook, and no other skill, is installed.
#
# Safe to re-run: files are replaced in place, each hook entry is replaced
# rather than added again, and settings.json is backed up only when it changes.
#
# Usage: bash memory-only/install.sh   (or: just install)
set -euo pipefail

FORK=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLAUDE="$HOME/.claude"
SKILLS_WANTED=(memory-audit memory-archive skill-forge)
TOOLS=(memory-index.sh memory-verify.sh memory-fix.sh memory-provenance.sh)
HOOKS=(memory-lint.sh memory-lint-stop.sh plan-to-html.sh)

for tool in jq git; do
  command -v "$tool" >/dev/null || { echo "install: $tool is required" >&2; exit 1; }
done

# place SRC DEST [MODE]: copy beside DEST and rename over it, so a hook that runs
# during the install never reads a half-written file (as upstream install.sh).
place() {
  local tmp="$2.tmp.$$"
  cp -p "$1" "$tmp" && { [[ -z "${3:-}" ]] || chmod "$3" "$tmp"; } && mv -f "$tmp" "$2"
}

mkdir -p "$CLAUDE/hooks/lib" "$CLAUDE/rules" "$CLAUDE/skills" "$CLAUDE/state/sessions" "$CLAUDE/plans-html"

for t in "${TOOLS[@]}"; do place "$FORK/bin/$t" "$CLAUDE/$t" 755; done
place "$FORK/hooks/lib.sh" "$CLAUDE/hooks/lib.sh" 755
for f in "$FORK"/hooks/lib/*.sh; do place "$f" "$CLAUDE/hooks/lib/${f##*/}" 755; done
for h in "${HOOKS[@]}"; do place "$FORK/hooks/$h" "$CLAUDE/hooks/$h" 755; done
place "$FORK/memory-only/hooks/memory-session-start.sh" "$CLAUDE/hooks/memory-session-start.sh" 755
place "$FORK/memory-only/rules/memory-writes.md" "$CLAUDE/rules/memory-writes.md" 644
echo "  ✓ tools, hooks and libs in $CLAUDE; rule rules/memory-writes.md"

# --- skills: only SKILLS_WANTED, from the pinned claude-code-skills release ---
pin() { sed -n "s/^$1=//p" "$FORK/config/skills.pin"; }
PIN_URL=$(pin url) PIN_TAG=$(pin tag) PIN_COMMIT=$(pin commit)
SRC="${XDG_CACHE_HOME:-$HOME/.cache}/claude-code-skills"
if [[ -d "$SRC/.git" ]]; then
  git -C "$SRC" fetch -q --tags --force origin
else
  git clone -q "$PIN_URL" "$SRC"
fi
# The cache belongs to this installer: --force and clean drop any local edit or
# stray file, so only the pinned release's bytes are ever installed.
git -C "$SRC" -c advice.detachedHead=false checkout -q --force "$PIN_TAG"
git -C "$SRC" clean -q -f -d -x
AT=$(git -C "$SRC" rev-parse HEAD)
[[ "$AT" == "$PIN_COMMIT" ]] || {
  echo "install: $PIN_TAG of $PIN_URL is $AT, but config/skills.pin says $PIN_COMMIT; skills not installed" >&2
  exit 1
}
# The same files upstream's skills install.sh copies: SKILL.md, *.example.toml
# and bin/ into ~/.claude/skills/<name>; templates/ into the data dir, never
# under ~/.claude/skills, so no template can be read as a skill.
for name in "${SKILLS_WANTED[@]}"; do
  s="$SRC/skills/$name" d="$CLAUDE/skills/$name"
  [[ -f "$s/SKILL.md" ]] || { echo "install: $PIN_TAG has no skills/$name" >&2; exit 1; }
  mkdir -p "$d"
  place "$s/SKILL.md" "$d/SKILL.md"
  for f in "$s"/*.example.toml; do
    if [[ -f "$f" ]]; then place "$f" "$d/${f##*/}"; fi
  done
  if [[ -d "$s/bin" ]]; then
    rm -rf "$d/bin" && mkdir -p "$d/bin"   # bin/ is release-owned: drop tools the release removed
    for f in "$s"/bin/*; do
      if [[ -f "$f" ]]; then place "$f" "$d/bin/${f##*/}"; fi
    done
  fi
  if [[ -d "$s/templates" ]]; then
    data="${XDG_DATA_HOME:-$HOME/.local/share}/$name"
    mkdir -p "$data" && rm -rf "$data/templates.new"
    cp -R "$s/templates" "$data/templates.new" && rm -rf "$data/templates" && mv "$data/templates.new" "$data/templates"
  fi
done
echo "  ✓ skills ${SKILLS_WANTED[*]} ($PIN_TAG)"

# --- settings.json: one entry per installed hook, others left as they are ----
SETTINGS="$CLAUDE/settings.json"
[[ -f "$SETTINGS" ]] || (umask 077 && echo '{}' > "$SETTINGS")
# The new file starts as a copy, so it has settings.json's mode before any
# merged content is written into it: a private settings.json stays private.
NEW="$SETTINGS.new.$$"
trap 'rm -f "$NEW"' EXIT
cp -p "$SETTINGS" "$NEW"
jq '
  def ours: test("\\.claude/hooks/(memory-lint|memory-lint-stop|memory-session-start|plan-to-html)\\.sh");
  def cmd($file): {type: "command", command: ("bash \"$HOME/.claude/hooks/" + $file + "\"")};
  .hooks = ((.hooks // {})
    | map_values(map(.hooks |= map(select((.command // "") | ours | not)))
                 | map(select((.hooks // []) | length > 0)))
    | with_entries(select(.value | length > 0))
    | .SessionStart += [{hooks: [cmd("memory-session-start.sh") + {timeout: 30}]}]
    | .PostToolUse  += [{matcher: "Write|Edit|MultiEdit", hooks: [cmd("memory-lint.sh")]}]
    | .Stop         += [{hooks: [cmd("memory-lint-stop.sh")]}]
    | .PreToolUse   += [{matcher: "ExitPlanMode", hooks: [cmd("plan-to-html.sh") + {async: true}]}])
' "$SETTINGS" > "$NEW"
if cmp -s <(jq -S . "$SETTINGS") <(jq -S . "$NEW"); then
  rm -f "$NEW"
  echo "  ✓ settings.json (already up to date)"
else
  BACKUP="$SETTINGS.bak-memory-only-$(date +%Y%m%d%H%M%S)"
  cp -p "$SETTINGS" "$BACKUP"
  mv -f "$NEW" "$SETTINGS"
  echo "  ✓ settings.json (hooks merged; backup: $BACKUP)"
fi
