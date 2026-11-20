#!/usr/bin/env bash
# SessionStart hook for the memory-only install: the memory parts of upstream
# hooks/session-start.sh and nothing else.
#
# Kept from upstream, unchanged: input parsing, the time budget and claim(), and
# "keep the memory index in tier order" (memory-index.sh, run only when the index
# is under pressure and changed since the last run). Left out: git context,
# worktree records, the host-binary check, the harness-release nudge, disk and
# transcript warnings and the Bash-guard timing log.
#
# One change: upstream prunes memory-lint's pending lists once per
# harness-update.sh disk measurement, which this install does not run. Here the
# prune runs once per day instead.
#
# Synced with upstream hooks/session-start.sh at 5165ad3. After an upstream
# merge, `just upstream-diff` shows whether that file changed; port changes to
# the sections above by hand.
if [[ "$0" == */* ]]; then source "${0%/*}/lib.sh"; else source ./lib.sh; fi   # dirname "$0", with no process

read_input
# One jq for the three fields, where jq_get would start one each. @sh quotes
# every value for the eval; with no jq, or input that is not an object, all stay empty.
SOURCE="" SESSION_ID="" LAUNCH_DIR=""
if command -v jq &>/dev/null; then
  eval "$(printf '%s\n' "$INPUT" | jq -r '@sh "SOURCE=\(.source // "") SESSION_ID=\(.session_id // "") LAUNCH_DIR=\(.cwd // "")"' 2>/dev/null)"
fi

# --- time budget -------------------------------------------------------------
# A section that would start past the budget is skipped and named on one line at
# exit. settings.json's 30 s timeout is the hard stop.
BUDGET=${CLAUDE_SESSION_START_BUDGET:-3} SECONDS=0
SKIPPED=""
in_budget() { (( SECONDS < BUDGET )) && return 0; SKIPPED="$SKIPPED $1"; return 1; }
trap '[[ -z "$SKIPPED" ]] || printf "\nsession-start: past its %s s budget, skipped:%s\n" "$BUDGET" "$SKIPPED"' EXIT

# claim FILE STAMP: true for one of the sessions that race to do what STAMP names
# (a day's prune, one state of an index), so a resume storm does it once. A
# noclobber create is atomic, starts no process and never expires: a run killed
# after it claims loses that one run. The winner clears older claims.
claim() {
  local c="$1.claim.${2//[^A-Za-z0-9._-]/_}" o old=()
  [[ -w "${1%/*}" ]] || return 0   # an unwritable state folder: every session, as before
  set -C; { : > "$c"; } 2>/dev/null || { set +C; return 1; }; set +C
  for o in "$1".claim.*; do [[ "$o" == "$c" ]] || old+=("$o"); done
  [[ ${#old[@]} -eq 0 ]] || rm -f "${old[@]}"
}

STATE_DIR=$(expand_tilde "${CLAUDE_STATE_DIR:-$HOME/.claude/state/sessions}")

# --- keep the memory index in tier order, when that can matter --------------
# MEMORY.md is cut tail-first at 200 lines and the memory writer appends at the
# end, so a feedback_ entry can land past the cut, where it never loads.
# memory-index.sh restores tier order as a pure permutation. It runs only when
# all three hold:
#   - the index is under pressure (memory-lint.sh's thresholds);
#   - the index changed since the last run (mtime and size, stamped below);
#   - auto-dream's .consolidate-lock is older than its 1 h TTL: a younger one
#     means the CLI's own consolidation may be rewriting this store.
# Only THIS session's store: the others are not being loaded here.
PROJECTS_DIR=$(expand_tilde "${CLAUDE_MEMORY_PROJECTS_DIR:-$HOME/.claude/projects}")
[[ -z "$LAUNCH_DIR" ]] && LAUNCH_DIR="$PWD"
# The store slug is the launch path with every non-alphanumeric a dash, as the
# CLI does it. A path over 200 characters also gets a hash suffix; not found, skipped.
STORE_SLUG=$(store_slug "$LAUNCH_DIR")
MEM_DIR="$PROJECTS_DIR/$STORE_SLUG/memory"
IDX_LINES=0 IDX_BYTES=0
[[ -f "$MEM_DIR/MEMORY.md" ]] && read -r IDX_LINES IDX_BYTES < <(wc -lc < "$MEM_DIR/MEMORY.md")
_hook_dir=${0%/*}; [[ "$_hook_dir" == "$0" ]] && _hook_dir=.
# shellcheck source=lib/memory-limits.sh
if source "$_hook_dir/lib/memory-limits.sh" 2>/dev/null && memory_pressure "$IDX_LINES" "$IDX_BYTES" \
   && in_budget memory-index; then
  STAMP_FILE="$STATE_DIR/memory-index/$STORE_SLUG"
  STAMP="$(date -r "$MEM_DIR/MEMORY.md" +%s 2>/dev/null) $IDX_BYTES"
  LOCK_FRESH=""
  [[ -f "$MEM_DIR/.consolidate-lock" ]] && LOCK_FRESH=$(find "$MEM_DIR/.consolidate-lock" -mmin -60 2>/dev/null)
  if [[ "$(head -1 "$STAMP_FILE" 2>/dev/null)" != "$STAMP" ]] && [[ -z "$LOCK_FRESH" ]]; then
    INDEX_TOOL=""
    for cand in "$(dirname "$0")/../memory-index.sh" "$(dirname "$0")/../bin/memory-index.sh"; do
      [[ -f "$cand" ]] && INDEX_TOOL="$cand" && break
    done
    # Silent: a pure permutation leaves the model nothing to act on. Stamped
    # after the write so the stamp records the index as it is now.
    [[ -d "$STATE_DIR/memory-index" ]] || mkdir -p "$STATE_DIR/memory-index" 2>/dev/null
    if [[ -n "$INDEX_TOOL" ]] && claim "$STAMP_FILE" "$STAMP"; then
      CLAUDE_MEMORY_PROJECTS_DIR="$PROJECTS_DIR" \
        bash "$INDEX_TOOL" --store "$STORE_SLUG" --write >/dev/null 2>&1 || true
      printf '%s %s\n' "$(date -r "$MEM_DIR/MEMORY.md" +%s 2>/dev/null)" "$(wc -c < "$MEM_DIR/MEMORY.md" | tr -d ' ')" > "$STAMP_FILE" 2>/dev/null
    fi
  fi
fi

# --- memory-lint's pending lists ----------------------------------------------
# hooks/memory-lint-stop.sh clears a session's list at Stop. A turn that ended by
# interrupt never reaches Stop, so its list stays: once a day, one detached find
# removes the lists a day old.
if [[ -d "$STATE_DIR/lint-pending" ]] && in_budget lint-pending-prune \
   && claim "$STATE_DIR/lint-pending-prune" "$(date +%F)"; then
  ( find "$STATE_DIR/lint-pending" -type f -mtime +0 -delete ) >/dev/null 2>&1 &
fi
