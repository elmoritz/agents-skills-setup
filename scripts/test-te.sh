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
# Case types:
#   config/<name>/  — a config.yaml (+ optional agents/); runs `te config
#                     validate <path>`. Golden: golden/config/<name>.out.
#   cli/<name>/     — an `argv` file (one te argument per line) + any project
#                     tree the command reads; runs `te <argv...>` with cwd set to
#                     the case dir. Golden: golden/cli/<name>.out.
#   read/<name>/    — like cli/, but the golden is the BYTE-EXACT stdout (no
#                     `--- exit` line appended, no $() trailing-newline strip),
#                     so `te read`'s body round-trip (trailing whitespace, final
#                     newline) is actually asserted. Exit must be 0.
# cli/config goldens are captured stdout+stderr + a final `--- exit: N` line.
# A standalone deps.awk check (AC: runnable without going through te) closes out.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

TE=.claude/scripts/te
TE_ABS="$PWD/$TE"
UPDATE=0
[ "${1:-}" = "--update" ] && UPDATE=1
fail=0
count=0

# ---- structural assertion: only `te` carries the exec bit in each bundle ----
check_exec_bits() {
  local bundle f
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

# diff a rendered result against a golden, or update it.
check_golden() {
  local golden=$1 rendered=$2 name=$3
  if [ "$UPDATE" -eq 1 ]; then
    mkdir -p "$(dirname "$golden")"
    printf '%s\n' "$rendered" > "$golden"
    echo "updated $name"
    return
  fi
  if [ ! -f "$golden" ]; then
    echo "FAIL [$name]: no golden ($golden). Run scripts/test-te.sh --update."; fail=1; return
  fi
  if ! diff -u "$golden" <(printf '%s\n' "$rendered") >/dev/null; then
    echo "FAIL [$name]: output differs from golden:"
    diff -u --label "$golden" --label "$name (actual)" "$golden" <(printf '%s\n' "$rendered") || true
    fail=1
  fi
}

run_config_case() {
  local dir=$1 name got rc
  name=$(basename "$dir")
  set +e; got=$("$TE" config validate "$dir/config.yaml" 2>&1); rc=$?; set -e
  check_golden "tests/golden/config/$name.out" "$got"$'\n'"--- exit: $rc" "config/$name"
  count=$((count + 1))
}

run_cli_case() {
  local dir=$1 name got rc
  name=$(basename "$dir")
  local argv=()
  while IFS= read -r a; do argv+=("$a"); done < "$dir/argv"
  set +e; got=$(cd "$dir" && "$TE_ABS" "${argv[@]}" 2>&1); rc=$?; set -e
  check_golden "tests/golden/cli/$name.out" "$got"$'\n'"--- exit: $rc" "cli/$name"
  count=$((count + 1))
}

# read/ case: byte-exact stdout comparison so the body round-trip AC is real.
run_read_case() {
  local dir=$1 name out rc
  name=$(basename "$dir")
  local argv=()
  while IFS= read -r a; do argv+=("$a"); done < "$dir/argv"
  out=$(mktemp)
  set +e; ( cd "$dir" && "$TE_ABS" "${argv[@]}" ) > "$out" 2>/dev/null; rc=$?; set -e
  local golden="tests/golden/read/$name.out"
  if [ "$UPDATE" -eq 1 ]; then
    mkdir -p "$(dirname "$golden")"; cp "$out" "$golden"; echo "updated read/$name"; rm -f "$out"; count=$((count + 1)); return
  fi
  if [ "$rc" -ne 0 ]; then echo "FAIL [read/$name]: exit $rc (expected 0)"; fail=1; fi
  if [ ! -f "$golden" ]; then
    echo "FAIL [read/$name]: no golden ($golden). Run scripts/test-te.sh --update."; fail=1
  elif ! diff -u "$golden" "$out" >/dev/null; then
    echo "FAIL [read/$name]: byte-exact stdout differs from golden:"
    diff -u --label "$golden" --label "read/$name (actual)" "$golden" "$out" || true
    fail=1
  fi
  rm -f "$out"; count=$((count + 1))
}

# A title carrying a literal newline can't be encoded in the one-arg-per-line
# argv format, so cover the AC's newline case with a direct invocation.
run_msg_newline() {
  local cfg=tests/fixtures/cli/msg-claim/config.yaml got rc
  [ -f "$cfg" ] || return 0
  set +e
  got=$("$TE" msg claim --id TE-1 --title "$(printf 'line one\nline two')" "$cfg" 2>&1); rc=$?
  set -e
  check_golden "tests/golden/misc/msg-newline.out" "$got"$'\n'"--- exit: $rc" "misc/msg-newline"
  count=$((count + 1))
}

# deps.awk must be runnable standalone against a fixture edge list (AC).
run_deps_standalone() {
  local edges=tests/fixtures/edges/cycle.txt got rc
  [ -f "$edges" ] || return 0
  set +e; got=$(awk -f .claude/scripts/lib/deps.awk -v start=A "$edges"); rc=$?; set -e
  check_golden "tests/golden/misc/deps-standalone.out" "$got"$'\n'"--- exit: $rc" "misc/deps-standalone"
  count=$((count + 1))
}

check_exec_bits
if [ ! -x "$TE" ]; then echo "Cannot run: $TE is not executable." >&2; exit 1; fi

for dir in tests/fixtures/config/*/; do
  [ -f "${dir}config.yaml" ] || continue
  run_config_case "${dir%/}"
done
for dir in tests/fixtures/cli/*/; do
  [ -f "${dir}argv" ] || continue
  run_cli_case "${dir%/}"
done
for dir in tests/fixtures/read/*/; do
  [ -f "${dir}argv" ] || continue
  run_read_case "${dir%/}"
done
run_msg_newline
run_deps_standalone

if [ "$UPDATE" -eq 1 ]; then echo "goldens updated."; exit 0; fi
if [ "$fail" -ne 0 ]; then echo "test-te: FAIL" >&2; exit 1; fi
echo "test-te: ok ($count cases)"
