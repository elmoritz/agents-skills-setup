#!/usr/bin/env bash
# Guard against drift between the .claude and .agents agent bundles.
#
# The two bundles mirror each other; any logic change must land in both in the
# same commit (see AGENTS.md § Keeping the bundles in sync). `.agents/` serves
# every AGENTS.md-class assistant (Codex, Antigravity, Gemini CLI, Copilot);
# the per-platform entry points under .agents/workflows/, .gemini/, .codex/, and
# .github/agents/ are generated routers, gated by scripts/gen-adapters.sh
# --check rather than mirrored. The default gate (also --staged / --base) runs
# four checks:
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

# name:claude-path:agents-path
PAIRS="
init:.claude/commands/ticket/init.md:.agents/skills/ticket-init/SKILL.md
new:.claude/commands/ticket/new.md:.agents/skills/ticket-new/SKILL.md
refine:.claude/commands/ticket/refine.md:.agents/skills/ticket-refine/SKILL.md
pick:.claude/commands/ticket/pick.md:.agents/skills/ticket-pick/SKILL.md
review:.claude/commands/ticket/review.md:.agents/skills/ticket-review/SKILL.md
reject:.claude/commands/ticket/reject.md:.agents/skills/ticket-reject/SKILL.md
close:.claude/commands/ticket/close.md:.agents/skills/ticket-close/SKILL.md
engine:.claude/skills/ticket-engine/SKILL.md:.agents/skills/ticket-engine/SKILL.md
milestone-sync:.claude/skills/milestone-sync/SKILL.md:.agents/skills/milestone-sync/SKILL.md
grill-me:.claude/skills/grill-me/SKILL.md:.agents/skills/grill-me/SKILL.md
readme:.claude/README.md:.agents/README.md
challenger:.claude/agents/challenger.md:.agents/agents/challenger.md
code-challenger:.claude/agents/code-challenger.md:.agents/agents/code-challenger.md
code-reviewer:.claude/agents/code-reviewer.md:.agents/agents/code-reviewer.md
code-simplifier:.claude/agents/code-simplifier.md:.agents/agents/code-simplifier.md
test-adequacy-reviewer:.claude/agents/test-adequacy-reviewer.md:.agents/agents/test-adequacy-reviewer.md
tpl-perf-expert:.claude/references/research-agents/perf-expert.md:.agents/references/research-agents/perf-expert.md
tpl-language-expert:.claude/references/research-agents/language-expert.md:.agents/references/research-agents/language-expert.md
tpl-precedent-researcher:.claude/references/research-agents/precedent-researcher.md:.agents/references/research-agents/precedent-researcher.md
tpl-docs-researcher:.claude/references/research-agents/docs-researcher.md:.agents/references/research-agents/docs-researcher.md
tpl-api-docs-researcher:.claude/references/research-agents/api-docs-researcher.md:.agents/references/research-agents/api-docs-researcher.md
tpl-design-spec-researcher:.claude/references/research-agents/design-spec-researcher.md:.agents/references/research-agents/design-spec-researcher.md
tpl-web-researcher:.claude/references/research-agents/web-researcher.md:.agents/references/research-agents/web-researcher.md
"

# Files that legitimately exist on one side only. Exact paths, or prefixes
# ending in '/'. Any tracked file under .claude/ or .agents/ that is neither
# here, in PAIRS, nor under a DIR_PAIRS directory fails the coverage check. The
# generated adapters (.agents/workflows/, .gemini/, .codex/, .github/agents/)
# are covered by scripts/gen-adapters.sh --check instead.
IGNORE="
.claude/settings.json
.claude/references/
.claude/config.yaml
.agents/config.yaml
.agents/workflows/
"

# name:claude-dir:agents-dir — recursively mirrored directories. Every tracked
# file under one side must exist under the other, be byte-identical, AND carry
# the same git mode (so a bundle copied without the te exec bit fails here, not
# just in the test harness). The te CLI derives its bundle dir from its own path
# (see .claude/scripts/te), so the two copies are byte-identical by construction
# and need none of the normalize/canon machinery the file PAIRS rely on.
DIR_PAIRS="
scripts:.claude/scripts/:.agents/scripts/
"

# Pairs whose two mirrors must be logic-identical (after frontmatter + fence
# stripping and normalization). The engine and the review agents carry the
# densest shared logic and diverge only mechanically between bundles, so they
# get the hard equivalence gate. Everything else (commands, skills, the
# human-facing READMEs) legitimately rephrases invocation/gate mechanics per
# platform and relies on the pairing check + the advisory `--equiv` instead.
EQUIV_CHECK="engine challenger code-challenger code-reviewer code-simplifier test-adequacy-reviewer tpl-perf-expert tpl-language-expert tpl-precedent-researcher tpl-docs-researcher tpl-api-docs-researcher tpl-design-spec-researcher tpl-web-researcher"

# Canonicalize the documented intentional differences to common tokens so
# whatever remains is real drift. Reads stdin, writes stdout. The bundle prefix
# is one of those differences: `.claude`, `.agents`, and the pre-relocation
# `.github/<bundle-subpath>` all collapse to the same token, so a mirror is
# compared on what it says, not on where it lives.
normalize() {
  sed -E \
      -e 's|\.claude|.agents|g' \
      -e 's#\.github#.agents#g' \
      -e 's#(agents/[a-z0-9-]+)\.agent\.md#\1.md#g' \
      -e 's|/ticket:|/ticket-|g' \
      -e 's/\$ARGUMENTS/«ARGS»/g' \
      -e 's/Copilot/«ASSISTANT»/g' \
      -e 's/Codex/«ASSISTANT»/g' \
      -e 's/Antigravity/«ASSISTANT»/g' \
      -e 's/Gemini CLI/«ASSISTANT»/g' \
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
  done < <(git ls-files -- .claude .agents)
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

check_adapters() {
  # The per-platform entry points are generated from the canonical bundle, so
  # they can't drift by hand-edit — they can only go stale. One command decides.
  if ! scripts/gen-adapters.sh --check >/dev/null 2>&1; then
    scripts/gen-adapters.sh --check 2>&1 | sed 's/^/FAIL [adapters]: /' >&2
    return 1
  fi
  return 0
}

# True when a file's change is invisible to canon() — i.e. it moved, or only its
# own bundle prefix was rewritten, and no logic changed. Follows renames so a
# relocated bundle compares against its pre-move blob.
canon_unchanged() { # canon_unchanged <path-now> <source>
  local now="$1" source="${2:-}" base old tmp
  case "$source" in
    --staged) base="HEAD" ;;
    "")       base="HEAD" ;;
    *)        base="${source%%...*}" ;;
  esac
  old=$(git diff --name-status -M "$base" 2>/dev/null \
        | awk -v n="$now" '$1 ~ /^R/ && $3 == n { print $2; exit }')
  [ -n "$old" ] || old="$now"
  git cat-file -e "$base:$old" 2>/dev/null || return 1
  tmp=$(mktemp); git show "$base:$old" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  if diff -q <(canon "$tmp") <(canon "$now") >/dev/null 2>&1; then
    rm -f "$tmp"; return 0
  fi
  rm -f "$tmp"; return 1
}

mode_check() {
  local source="${1:-}" changed fail=0
  check_coverage || fail=1
  check_equiv || fail=1
  check_dir_pairs || fail=1
  check_adapters || fail=1
  case "$source" in
    --staged) changed=$(git diff --name-only --cached) ;;
    "")       changed=$(git diff --name-only HEAD) ;;
    *)        changed=$(git diff --name-only "$source") ;;
  esac
  for entry in $PAIRS; do
    IFS=: read -r name c g <<<"$entry"
    local in_c=0 in_g=0 lone
    grep -qxF "$c" <<<"$changed" && in_c=1
    grep -qxF "$g" <<<"$changed" && in_g=1
    if [ "$in_c" -ne "$in_g" ]; then
      [ "$in_c" -eq 1 ] && lone="$c" || lone="$g"
      # For an equivalence-gated pair, equivalence is the stronger statement: if
      # the mirrors still say the same thing, no logic moved one-sidedly.
      if is_equiv_checked "$name" && diff -q <(canon "$c") <(canon "$g") >/dev/null 2>&1; then
        continue
      fi
      # A one-sided edit that survives canon() unchanged carried no logic — a
      # bundle relocation or a path rewrite the normalizer already accounts for.
      # The mirror has nothing to mirror, so this is not drift.
      if canon_unchanged "$lone" "$source"; then
        continue
      fi
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
        # Byte-identical already (check_dir_pairs asserts that separately): the
        # one-sided change was a relocation, so the mirror has nothing to track.
        if diff -q "$f" "$mirror" >/dev/null 2>&1; then
          continue
        fi
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
  - FAIL [adapters]      a generated platform entry point is stale — run
                         scripts/gen-adapters.sh and commit the result.

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
