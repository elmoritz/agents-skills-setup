#!/usr/bin/env bash
# Guard against drift between the .claude and .github agent bundles.
#
# The two bundles mirror each other; any logic change must land in both in the
# same commit (see AGENTS.md § Keeping the bundles in sync). Two modes:
#
#   Pairing check (default) — if a file in a mirrored pair changed but its
#   mirror did not change in the same range, fail. Also fails if any tracked
#   file under the bundles is neither in PAIRS nor in IGNORE (coverage check —
#   closes drift-by-addition). This is the hard gate used by the pre-commit
#   hook and CI.
#
#   --diff [name] — print a normalized unified diff for one pair (or all).
#   The normalization maps the documented intentional differences (config
#   path, command naming, gate mechanism) onto common tokens; whatever remains
#   is either more intentional platform phrasing or real drift — review it.
#   The diff covers the whole file including frontmatter; it is advisory and
#   is the manual tool for reviewing content drift the pairing check can't see.
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
reject:.claude/commands/ticket/reject.md:.github/skills/ticket-reject/SKILL.md
close:.claude/commands/ticket/close.md:.github/skills/ticket-close/SKILL.md
engine:.claude/skills/ticket-engine/SKILL.md:.github/skills/ticket-engine/SKILL.md
milestone-sync:.claude/skills/milestone-sync/SKILL.md:.github/skills/milestone-sync/SKILL.md
grill-me:.claude/skills/grill-me/SKILL.md:.github/skills/grill-me/SKILL.md
readme:.claude/README.md:.github/README.md
"

# Files that legitimately exist on one side only. Exact paths, or prefixes
# ending in '/'. Any tracked file under .claude/ or .github/skills/ that is
# neither here nor in PAIRS fails the coverage check.
IGNORE="
.claude/settings.json
.claude/references/
.claude/config.yaml
.github/config.yaml
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

check_coverage() {
  # Every tracked file under the bundles must be in PAIRS or IGNORE, so a new
  # file added to one bundle without a mirror is caught even though the
  # pairing check (which only sees changed pairs) cannot see it.
  local fail=0 f entry c g ignored pat
  while IFS= read -r f; do
    for entry in $PAIRS; do
      IFS=: read -r _ c g <<<"$entry"
      [ "$f" = "$c" ] || [ "$f" = "$g" ] && continue 2
    done
    ignored=0
    for pat in $IGNORE; do
      case "$pat" in
        */) case "$f" in "$pat"*) ignored=1 ;; esac ;;
        *)  [ "$f" = "$pat" ] && ignored=1 ;;
      esac
    done
    [ "$ignored" -eq 1 ] && continue
    echo "FAIL [coverage]: $f is in neither PAIRS nor IGNORE (scripts/check-bundle-sync.sh) — add a mirror + PAIRS entry, or list it in IGNORE."
    fail=1
  done < <(git ls-files -- .claude .github/skills)
  return "$fail"
}

mode_check() {
  local source="${1:-}" changed fail=0
  check_coverage || fail=1
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
