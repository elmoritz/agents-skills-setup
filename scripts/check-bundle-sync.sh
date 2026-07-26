#!/usr/bin/env bash
# Guard against drift between the .claude and .github agent bundles.
#
# The two bundles mirror each other; any logic change must land in both in the
# same commit (see AGENTS.md § Keeping the bundles in sync). The default gate
# (also --staged / --base) runs three checks:
#
#   Pairing check — if a file in a mirrored pair changed but its mirror did not
#   change in the same range, fail. Catches "edited one, forgot the other".
#
#   Coverage check — every tracked file under the bundles must be in PAIRS or
#   IGNORE. Catches drift-by-addition (a new file with no mirror).
#
#   Equivalence check — for the logic-dense pairs (the engine + the review
#   agents; see EQUIV_CHECK), strip YAML frontmatter and any
#   <!-- sync:divergent --> … <!-- sync:end --> regions, normalize the
#   documented intentional differences to common tokens, and require the two
#   mirrors to be byte-identical. Residual difference is real content drift
#   ("edited both, but differently") and fails the gate — the check the pairing
#   check structurally cannot make. Commands/skills rephrase gate mechanics per
#   platform throughout their bodies, so they stay on pairing + advisory --equiv.
#
# Intentional, irregular per-platform prose (invocation style, frontmatter,
# gate-mechanism wording) is excluded two ways: frontmatter is stripped
# automatically, and anything wrapped in a <!-- sync:divergent --> fence on
# both sides is skipped. Everything else must agree.
#
# Usage:
#   scripts/check-bundle-sync.sh                 # full gate, worktree vs HEAD
#   scripts/check-bundle-sync.sh --staged        # full gate, staged changes (pre-commit)
#   scripts/check-bundle-sync.sh --base RANGE    # full gate, e.g. origin/main...HEAD
#   scripts/check-bundle-sync.sh --diff  [name]  # advisory: raw normalized diff (whole file)
#   scripts/check-bundle-sync.sh --equiv [name]  # show the equivalence residual to fence or fix

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
challenger:.claude/agents/challenger.md:.github/agents/challenger.agent.md
code-reviewer:.claude/agents/code-reviewer.md:.github/agents/code-reviewer.agent.md
code-simplifier:.claude/agents/code-simplifier.md:.github/agents/code-simplifier.agent.md
test-adequacy-reviewer:.claude/agents/test-adequacy-reviewer.md:.github/agents/test-adequacy-reviewer.agent.md
tpl-perf-expert:.claude/references/research-agents/perf-expert.md:.github/references/research-agents/perf-expert.agent.md
tpl-language-expert:.claude/references/research-agents/language-expert.md:.github/references/research-agents/language-expert.agent.md
tpl-precedent-researcher:.claude/references/research-agents/precedent-researcher.md:.github/references/research-agents/precedent-researcher.agent.md
tpl-docs-researcher:.claude/references/research-agents/docs-researcher.md:.github/references/research-agents/docs-researcher.agent.md
tpl-api-docs-researcher:.claude/references/research-agents/api-docs-researcher.md:.github/references/research-agents/api-docs-researcher.agent.md
tpl-design-spec-researcher:.claude/references/research-agents/design-spec-researcher.md:.github/references/research-agents/design-spec-researcher.agent.md
tpl-web-researcher:.claude/references/research-agents/web-researcher.md:.github/references/research-agents/web-researcher.agent.md
"

# Files that legitimately exist on one side only. Exact paths, or prefixes
# ending in '/'. Any tracked file under .claude/, .github/skills/,
# .github/agents/, or .github/scripts/ that is neither here, in PAIRS, nor under
# a DIR_PAIRS directory fails the coverage check.
IGNORE="
.claude/settings.json
.claude/references/
.claude/config.yaml
.github/config.yaml
"

# name:claude-dir:github-dir — recursively mirrored directories. Every tracked
# file under one side must exist under the other, be byte-identical, AND carry
# the same git mode (so a bundle copied without the te exec bit fails here, not
# just in the test harness). The te CLI derives its bundle dir from its own path
# (see .claude/scripts/te), so the two copies are byte-identical by construction
# and need none of the normalize/canon machinery the file PAIRS rely on.
DIR_PAIRS="
scripts:.claude/scripts/:.github/scripts/
"

# Pairs whose two mirrors must be logic-identical (after frontmatter + fence
# stripping and normalization). The engine and the review agents carry the
# densest shared logic and diverge only mechanically between bundles, so they
# get the hard equivalence gate. Everything else (commands, skills, the
# human-facing READMEs) legitimately rephrases invocation/gate mechanics per
# platform and relies on the pairing check + the advisory `--equiv` instead.
EQUIV_CHECK="engine challenger code-reviewer code-simplifier test-adequacy-reviewer tpl-perf-expert tpl-language-expert tpl-precedent-researcher tpl-docs-researcher tpl-api-docs-researcher tpl-design-spec-researcher tpl-web-researcher"

# Canonicalize the documented intentional differences to common tokens so
# whatever remains is real drift. Reads stdin, writes stdout.
normalize() {
  sed -e 's|\.claude|.github|g' \
      -e 's|/ticket:|/ticket-|g' \
      -e 's/\$ARGUMENTS/«ARGS»/g' \
      -e 's/Copilot/«ASSISTANT»/g' \
      -e 's/Claude/«ASSISTANT»/g' \
      -e 's/`AskUserQuestion`/«GATE»/g' \
      -e 's/AskUserQuestion/«GATE»/g' \
      -e 's/numbered list/«GATE»/g' \
      -e 's/NUMBERED LIST/«GATE»/g' \
      -e 's/^tools:.*/«TOOLS»/'
}

# Strip leading YAML frontmatter and <!-- sync:divergent --> … <!-- sync:end -->
# regions, normalize, then drop blank lines and trailing whitespace so that
# blank-line-only layout differences between mirrors don't count as drift (the
# output is only ever compared, never written back). Argument: a file path.
canon() {
  awk '
    NR == 1 && $0 == "---" { infm = 1; next }
    infm && $0 == "---"    { infm = 0; next }
    infm                   { next }
    /<!-- sync:divergent -->/ { skip = 1; next }
    /<!-- sync:end -->/       { skip = 0; next }
    skip { next }
    { print }
  ' "$1" | normalize | sed 's/[[:space:]]*$//' | awk 'NF'
}

is_equiv_checked() {
  local n="$1" s
  for s in $EQUIV_CHECK; do [ "$n" = "$s" ] && return 0; done
  return 1
}

mode_diff() {
  local want="${1:-}" found=0
  for entry in $PAIRS; do
    IFS=: read -r name c g <<<"$entry"
    [ -n "$want" ] && [ "$want" != "$name" ] && continue
    found=1
    echo "=== $name: $c <-> $g ==="
    diff -u --label "$c (normalized)" --label "$g (normalized)" \
      <(normalize < "$c") <(normalize < "$g") || true
    echo
  done
  if [ -n "$want" ] && [ "$found" -eq 0 ]; then
    echo "Unknown pair '$want'. Known pairs:" >&2
    for entry in $PAIRS; do echo "  ${entry%%:*}" >&2; done
    exit 2
  fi
}

mode_equiv() {
  local want="${1:-}" found=0
  for entry in $PAIRS; do
    IFS=: read -r name c g <<<"$entry"
    [ -n "$want" ] && [ "$want" != "$name" ] && continue
    found=1
    if is_equiv_checked "$name"; then
      echo "=== equiv $name [GATED]: $c <-> $g  (frontmatter + sync-divergent fences stripped, normalized) ==="
    else
      echo "=== equiv $name [advisory — not gated]: $c <-> $g ==="
    fi
    diff -u --label "$c (canon)" --label "$g (canon)" \
      <(canon "$c") <(canon "$g") || true
    echo
  done
  if [ -n "$want" ] && [ "$found" -eq 0 ]; then
    echo "Unknown pair '$want'. Known pairs:" >&2
    for entry in $PAIRS; do echo "  ${entry%%:*}" >&2; done
    exit 2
  fi
}

check_coverage() {
  # Every tracked file under the bundles must be in PAIRS, under a DIR_PAIRS
  # directory, or in IGNORE, so a new file added to one bundle without a mirror
  # is caught even though the pairing check (which only sees changed pairs)
  # cannot see it.
  local fail=0 f entry c g cd gd ignored pat
  while IFS= read -r f; do
    for entry in $PAIRS; do
      IFS=: read -r _ c g <<<"$entry"
      [ "$f" = "$c" ] || [ "$f" = "$g" ] && continue 2
    done
    for entry in $DIR_PAIRS; do
      IFS=: read -r _ cd gd <<<"$entry"
      case "$f" in "$cd"*|"$gd"*) continue 2 ;; esac
    done
    ignored=0
    for pat in $IGNORE; do
      case "$pat" in
        */) case "$f" in "$pat"*) ignored=1 ;; esac ;;
        *)  [ "$f" = "$pat" ] && ignored=1 ;;
      esac
    done
    [ "$ignored" -eq 1 ] && continue
    echo "FAIL [coverage]: $f is in neither PAIRS, a DIR_PAIRS directory, nor IGNORE (scripts/check-bundle-sync.sh) — add a mirror, or list it in IGNORE."
    fail=1
  done < <(git ls-files -- .claude .github/skills .github/agents .github/scripts)
  return "$fail"
}

check_dir_pairs() {
  # For each mirrored directory: every tracked file on one side must exist on
  # the other, be byte-identical, and share the same git mode. This is the
  # equivalence check the file PAIRS get, but by raw bytes — the two copies are
  # meant to be identical, so there is nothing to normalize.
  local fail=0 entry name cd gd f rel other m1 m2
  for entry in $DIR_PAIRS; do
    IFS=: read -r name cd gd <<<"$entry"
    while IFS= read -r f; do
      rel=${f#"$cd"}; other="$gd$rel"
      if [ ! -f "$other" ]; then
        echo "FAIL [dir:$name]: $f has no mirror at $other."; fail=1; continue
      fi
      if ! diff -q "$f" "$other" >/dev/null 2>&1; then
        echo "FAIL [dir:$name]: $f and $other differ — the two copies must be byte-identical."; fail=1
      fi
      m1=$(git ls-files -s -- "$f"     | awk '{print $1}')
      m2=$(git ls-files -s -- "$other" | awk '{print $1}')
      if [ -n "$m1" ] && [ "$m1" != "$m2" ]; then
        echo "FAIL [dir:$name]: mode $m1 ($f) != $m2 ($other) — the exec bit must match (only te is executable)."; fail=1
      fi
    done < <(git ls-files -- "$cd")
    while IFS= read -r f; do
      rel=${f#"$gd"}; other="$cd$rel"
      if [ ! -f "$other" ]; then
        echo "FAIL [dir:$name]: $f has no mirror at $other."; fail=1
      fi
    done < <(git ls-files -- "$gd")
  done
  return "$fail"
}

check_equiv() {
  # After stripping frontmatter + fenced-divergent regions and normalizing the
  # documented intentional differences, each pair's two mirrors must match. Any
  # residual is content drift the pairing check cannot see.
  local fail=0 entry name c g
  for entry in $PAIRS; do
    IFS=: read -r name c g <<<"$entry"
    is_equiv_checked "$name" || continue
    if ! diff -q <(canon "$c") <(canon "$g") >/dev/null 2>&1; then
      echo "FAIL [equiv:$name]: mirrors differ after normalization — unfenced content drift between $c and $g."
      fail=1
    fi
  done
  return "$fail"
}

mode_check() {
  local source="${1:-}" changed fail=0
  check_coverage || fail=1
  check_equiv || fail=1
  check_dir_pairs || fail=1
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
  # DIR_PAIRS pairing: a file changed under one mirrored dir but not the other.
  local cd gd f mirror
  for entry in $DIR_PAIRS; do
    IFS=: read -r name cd gd <<<"$entry"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$f" in
        "$cd"*) mirror="$gd${f#"$cd"}" ;;
        "$gd"*) mirror="$cd${f#"$gd"}" ;;
        *) continue ;;
      esac
      if ! grep -qxF "$mirror" <<<"$changed"; then
        echo "FAIL [dir:$name]: $f changed, but its mirror $mirror did not."
        fail=1
      fi
    done < <(printf '%s\n' "$changed" | grep -E "^(${cd}|${gd})" || true)
  done
  if [ "$fail" -ne 0 ]; then
    cat >&2 <<'EOF'

Bundle drift (see AGENTS.md "Keeping the bundles in sync"):
  - FAIL [<pair>]        one side changed without its mirror — edit both.
  - FAIL [equiv:<pair>]  the mirrors say different things — reconcile them, or
                         wrap the intentional difference in a
                         <!-- sync:divergent --> … <!-- sync:end --> fence.
  - FAIL [coverage]      a bundle file has no mirror + PAIRS entry.

Inspect a pair:
  scripts/check-bundle-sync.sh --equiv <name>   # the equivalence residual
  scripts/check-bundle-sync.sh --diff  <name>   # the full normalized diff
EOF
    exit 1
  fi
  echo "bundle-sync: ok (pairs changed together, coverage complete, mirrors equivalent)"
}

case "${1:-}" in
  --diff)   mode_diff "${2:-}" ;;
  --equiv)  mode_equiv "${2:-}" ;;
  --base)   mode_check "${2:?--base needs a git range, e.g. origin/main...HEAD}" ;;
  --staged) mode_check --staged ;;
  "")       mode_check "" ;;
  *)        echo "Usage: $0 [--staged | --base RANGE | --diff [pair] | --equiv [pair]]" >&2; exit 2 ;;
esac
