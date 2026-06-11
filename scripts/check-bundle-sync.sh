#!/usr/bin/env bash
# Guard against drift between the .claude and .github agent bundles.
#
# The two bundles mirror each other; any logic change must land in both in the
# same commit (see AGENTS.md § Keeping the bundles in sync). Two modes:
#
#   Pairing check (default) — if a file in a mirrored pair changed but its
#   mirror did not change in the same range, fail. This is the hard gate used
#   by the pre-commit hook and CI.
#
#   --diff [name] — print a normalized unified diff for one pair (or all).
#   The normalization maps the documented intentional differences (config
#   path, command naming, gate mechanism) onto common tokens; whatever remains
#   is either more intentional platform phrasing or real drift — review it.
#
# Usage:
#   scripts/check-bundle-sync.sh                 # pairing check, worktree vs HEAD
#   scripts/check-bundle-sync.sh --staged        # pairing check, staged changes only (pre-commit)
#   scripts/check-bundle-sync.sh --base RANGE    # pairing check, e.g. origin/main...HEAD
#   scripts/check-bundle-sync.sh --diff [name]   # normalized diff (all pairs or one)

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# name:claude-path:github-path
PAIRS="
init:.claude/commands/ticket/init.md:.github/skills/ticket-init/SKILL.md
new:.claude/commands/ticket/new.md:.github/skills/ticket-new/SKILL.md
refine:.claude/commands/ticket/refine.md:.github/skills/ticket-refine/SKILL.md
pick:.claude/commands/ticket/pick.md:.github/skills/ticket-pick/SKILL.md
review:.claude/commands/ticket/review.md:.github/skills/ticket-review/SKILL.md
close:.claude/commands/ticket/close.md:.github/skills/ticket-close/SKILL.md
engine:.claude/skills/ticket-engine/SKILL.md:.github/skills/ticket-engine/SKILL.md
milestone-sync:.claude/skills/milestone-sync/SKILL.md:.github/skills/milestone-sync/SKILL.md
grill-me:.claude/skills/grill-me/SKILL.md:.github/skills/grill-me/SKILL.md
"

normalize() {
  sed -e 's|\.claude/|.github/|g' \
      -e 's|/ticket:|/ticket-|g' \
      -e 's/`AskUserQuestion`/«GATE»/g' \
      -e 's/AskUserQuestion/«GATE»/g' \
      -e 's/numbered list/«GATE»/g' \
      -e 's/NUMBERED LIST/«GATE»/g' \
      "$1"
}

mode_diff() {
  local want="${1:-}" found=0
  for entry in $PAIRS; do
    IFS=: read -r name c g <<<"$entry"
    [ -n "$want" ] && [ "$want" != "$name" ] && continue
    found=1
    echo "=== $name: $c <-> $g ==="
    diff -u --label "$c (normalized)" --label "$g (normalized)" \
      <(normalize "$c") <(normalize "$g") || true
    echo
  done
  if [ -n "$want" ] && [ "$found" -eq 0 ]; then
    echo "Unknown pair '$want'. Known pairs:" >&2
    for entry in $PAIRS; do echo "  ${entry%%:*}" >&2; done
    exit 2
  fi
}

mode_check() {
  local source="${1:-}" changed fail=0
  case "$source" in
    --staged) changed=$(git diff --name-only --cached) ;;
    "")       changed=$(git diff --name-only HEAD) ;;
    *)        changed=$(git diff --name-only "$source") ;;
  esac
  for entry in $PAIRS; do
    IFS=: read -r name c g <<<"$entry"
    local in_c=0 in_g=0
    grep -qxF "$c" <<<"$changed" && in_c=1
    grep -qxF "$g" <<<"$changed" && in_g=1
    if [ "$in_c" -ne "$in_g" ]; then
      if [ "$in_c" -eq 1 ]; then
        echo "FAIL [$name]: $c changed, but its mirror $g did not."
      else
        echo "FAIL [$name]: $g changed, but its mirror $c did not."
      fi
      fail=1
    fi
  done
  if [ "$fail" -ne 0 ]; then
    cat >&2 <<'EOF'

Bundle drift: apply the same logic change to the mirror file (see AGENTS.md
"Keeping the bundles in sync"). To compare a pair:

  scripts/check-bundle-sync.sh --diff <name>
EOF
    exit 1
  fi
  echo "bundle-sync: ok (all mirrored pairs changed together or not at all)"
}

case "${1:-}" in
  --diff)   mode_diff "${2:-}" ;;
  --base)   mode_check "${2:?--base needs a git range, e.g. origin/main...HEAD}" ;;
  --staged) mode_check --staged ;;
  "")       mode_check "" ;;
  *)        echo "Usage: $0 [--staged | --base RANGE | --diff [pair-name]]" >&2; exit 2 ;;
esac
