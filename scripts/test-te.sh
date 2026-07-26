#!/usr/bin/env bash
# test-te.sh — golden-file tests for the te CLI. Plain bash, zero dependencies,
# fully offline (no network, no gh). Mirrors the normalized-diff idiom of
# check-bundle-sync.sh.
#
#   scripts/test-te.sh            run all cases, diff against tests/golden/
#   scripts/test-te.sh --update   regenerate goldens (NEVER run in CI; a changed
#                                  golden is a behavior change, justified in the
#                                  commit message)
#
# A case is a directory tests/fixtures/config/<name>/ holding a config.yaml (and
# optional agents/ for rules 16/17). The golden tests/golden/config/<name>.out
# is the captured stdout followed by a final `--- exit: N` line.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

TE=.claude/scripts/te
FIX=tests/fixtures/config
GOLD=tests/golden/config
UPDATE=0
[ "${1:-}" = "--update" ] && UPDATE=1

fail=0

# ---- structural assertion: only `te` carries the exec bit in each bundle ----
# A bundle copied without exec bits (or with the bit spread to lib files) is a
# real failure mode; assert it here so a bad copy fails loudly (AC).
check_exec_bits() {
  local bundle f base
  for bundle in .claude/scripts .github/scripts; do
    [ -d "$bundle" ] || { echo "FAIL [exec]: missing bundle dir $bundle"; fail=1; continue; }
    if [ ! -x "$bundle/te" ]; then
      echo "FAIL [exec]: $bundle/te is not executable — a bundle copied without exec bits."
      fail=1
    fi
    for f in "$bundle"/lib/*; do
      [ -e "$f" ] || continue
      if [ -x "$f" ]; then
        echo "FAIL [exec]: $f is executable but only te should be."
        fail=1
      fi
    done
  done
}

run_case() {
  local dir=$1 name got rc golden
  name=$(basename "$dir")
  golden="$GOLD/$name.out"
  set +e
  got=$("$TE" config validate "$dir/config.yaml" 2>&1)
  rc=$?
  set -e
  local rendered
  rendered="$got"$'\n'"--- exit: $rc"

  if [ "$UPDATE" -eq 1 ]; then
    mkdir -p "$GOLD"
    printf '%s\n' "$rendered" > "$golden"
    echo "updated $name"
    return
  fi

  if [ ! -f "$golden" ]; then
    echo "FAIL [$name]: no golden ($golden). Run scripts/test-te.sh --update."
    fail=1
    return
  fi
  if ! diff -u "$golden" <(printf '%s\n' "$rendered") >/dev/null; then
    echo "FAIL [$name]: output differs from golden:"
    diff -u --label "$golden" --label "$name (actual)" "$golden" <(printf '%s\n' "$rendered") || true
    fail=1
  fi
}

check_exec_bits
if [ ! -x "$TE" ]; then
  echo "Cannot run: $TE is not executable." >&2
  exit 1
fi
for dir in "$FIX"/*/; do
  [ -f "${dir}config.yaml" ] || continue
  run_case "${dir%/}"
done

if [ "$UPDATE" -eq 1 ]; then
  echo "goldens updated."
  exit 0
fi
if [ "$fail" -ne 0 ]; then
  echo "test-te: FAIL" >&2
  exit 1
fi
echo "test-te: ok ($(ls -d "$FIX"/*/ | wc -l | tr -d ' ') cases)"
