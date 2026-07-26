#!/usr/bin/env bash
# test-examples.sh — end-to-end smoke test over every committed example flavor
# (examples/<flavor>/). Offline, no network, no gh — CI-runnable.
#
# For every flavor: `te config validate` must pass (the config shape is what
# varies per flavor). For the seeded filesystem flavors, also exercise the real
# read path end to end: `te ledger validate`, `te read`, `te list pickable`,
# `te milestone scan`. The github read/list/milestone/projects MAPPING is covered
# exhaustively offline by tests/fixtures/gh/ (see scripts/test-te.sh); here the
# github flavors verify config validity per flavor.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
TE="$PWD/.claude/scripts/te"
fail=0 n=0

expect_ok() {  # description ; runs the rest as a command in the current dir
  local desc=$1; shift
  if ! "$@" >/dev/null 2>&1; then
    echo "FAIL [$desc]: \`$*\` did not exit 0"; fail=1
  fi
}

for dir in examples/*/; do
  name=$(basename "$dir")
  [ -f "$dir/.claude/config.yaml" ] || continue
  n=$((n + 1))
  backend=$(sed -n 's/^  type: //p' "$dir/.claude/config.yaml" | head -1)
  (
    cd "$dir"
    "$TE" config validate >/dev/null 2>&1 || { echo "FAIL [$name]: config validate"; exit 3; }
    if [ "$backend" = filesystem ]; then
      "$TE" ledger validate >/dev/null 2>&1 || { echo "FAIL [$name]: ledger validate"; exit 3; }
      # seeded flavors carry TE-001/002 (backlog) + TE-003 (done). Assert the
      # read path returns the RIGHT data, not merely exit 0.
      if ls proj/backlog/TE-001-* >/dev/null 2>&1; then
        r=$("$TE" read TE-001 2>/dev/null) || { echo "FAIL [$name]: read TE-001 crashed"; exit 3; }
        case "$r" in *"title=First task"*) ;; *) echo "FAIL [$name]: read TE-001 missing seeded title"; exit 3 ;; esac
        case "$r" in *"depends_on=TE-003"*) ;; *) echo "FAIL [$name]: read TE-001 missing ledger dep"; exit 3 ;; esac
        l=$("$TE" list pickable 2>/dev/null) || { echo "FAIL [$name]: list pickable crashed"; exit 3; }
        case "$l" in *"id=TE-001"*) ;; *) echo "FAIL [$name]: list pickable missing TE-001"; exit 3 ;; esac
        case "$l" in *"id=TE-002"*) ;; *) echo "FAIL [$name]: list pickable missing TE-002"; exit 3 ;; esac
        case "$l" in *"id=TE-003"*) echo "FAIL [$name]: list pickable wrongly includes done TE-003"; exit 3 ;; esac
        "$TE" milestone scan >/dev/null 2>&1 || { echo "FAIL [$name]: milestone scan crashed"; exit 3; }
      fi
    fi
  ) || fail=1
  echo "  ok: $name ($backend)"
done

if [ "$fail" -ne 0 ]; then echo "test-examples: FAIL" >&2; exit 1; fi
echo "test-examples: ok ($n flavors)"
