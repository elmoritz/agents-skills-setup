#!/usr/bin/env bash
# test-skill-ops.sh — for every example flavor, exercise the deterministic te
# operations each /ticket:* skill invokes against the ticket-engine, and assert
# they behave. This is the "does skill X's engine surface work on flavor Y"
# breadth check; the full write-path lifecycle is scripts/test-lifecycle.sh, and
# the per-operation goldens are scripts/test-te.sh.
#
# Skill -> engine operations exercised here:
#   /ticket:new     te id next · te slug · te validate-body · te effort-cap · te deps check
#   /ticket:refine  te validate-body · te effort-cap (promotion to backlog)
#   /ticket:pick    te list <pickable> --depends-satisfied · te read
#   /ticket:review  te read
#   /ticket:reject  te read
#   /ticket:close   te read
#   milestone-sync  te milestone scan
#
# Offline/CI-runnable. github read/list/deps/milestone need a live gh, so on the
# github flavors only the backend-independent operations run here (the github
# read path is covered by tests/fixtures/gh/ and scripts/live-gh-check.sh).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
TE="$PWD/.claude/scripts/te"
fail=0 n=0
tmpbody=$(mktemp)
printf '## goal\nDo it.\n\n## approach\nStep by step.\n\n## verification\nRun tests.\n' > "$tmpbody"
trap 'rm -f "$tmpbody"' EXIT

ok()      { local d=$1; shift; "$@" >/dev/null 2>&1 || { echo "  FAIL [$FL/$d]: \`$*\` exit!=0"; fail=1; }; }
notok()   { local d=$1; shift; "$@" >/dev/null 2>&1 && { echo "  FAIL [$FL/$d]: \`$*\` unexpectedly exit 0"; fail=1; } || true; }
has()     { local d=$1 want=$2; shift 2; case "$("$@" 2>/dev/null)" in *"$want"*) ;; *) echo "  FAIL [$FL/$d]: output lacks '$want'"; fail=1 ;; esac; }

for dir in examples/*/; do
  FL=$(basename "$dir"); [ -f "$dir/.claude/config.yaml" ] || continue
  n=$((n + 1))
  backend=$(sed -n 's/^  type: //p' "$dir/.claude/config.yaml" | head -1)
  ( cd "$dir"
    # --- /ticket:new + /ticket:refine (create-side ops; both backends) ---
    ok    "new:id-next"       "$TE" id next
    has   "new:slug"          "add-bee-hive-node-for-honey" "$TE" slug "Add bee hive node for honey production"
    has   "new:effort-ok"     "ok=true"  "$TE" effort-cap --effort M --role pickable
    notok "new:effort-cap"    "$TE" effort-cap --effort XL --role pickable
    has   "new:validate-body" "ok=true"  "$TE" validate-body --type tech --file "$tmpbody"
    ok    "new:msg"           "$TE" msg claim --id X --title "a title"

    if [ "$backend" = filesystem ]; then
      # deps check needs the ledger (filesystem graph source)
      ok  "new:deps-check"    "$TE" deps check TE-050 --depends-on TE-003
      # --- /ticket:pick ---
      has "pick:list"         "id=TE-001" "$TE" list pickable --depends-satisfied
      has "pick:read"         "id=TE-001" "$TE" read TE-001
      # --- /ticket:review, reject, close all load via read ---
      has "review/reject/close:read" "stage=" "$TE" read TE-001
      # --- milestone-sync ---
      ok  "milestone-sync:scan" "$TE" milestone scan
    fi
  ) || fail=1
  echo "  ok: $FL ($backend)"
done

if [ "$fail" -ne 0 ]; then echo "test-skill-ops: FAIL" >&2; exit 1; fi
echo "test-skill-ops: ok ($n flavors)"
