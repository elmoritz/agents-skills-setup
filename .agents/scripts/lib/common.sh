# common.sh — shared shell helpers for te. Sourced by te; not executable.
# bash 3.2 clean: no declare -A, no mapfile, no ${x,,}.
#
# Relies on TE_SELF (dir of the te entrypoint) and TE_BUNDLE (its parent, the
# bundle root — .claude or .agents), both exported by te before sourcing.

# Emit an `A <TAB> name` record for every agent file in $1, stripping either
# bundle's suffix (.agent.md on github, .md on claude) so a fixture's agents
# resolve regardless of which bundle's te is running. awk can't stat the
# filesystem, so rules 16/17 consume these records instead (see validate.awk).
te_agent_records() {
  local d="$1" f b
  [ -d "$d" ] || return 0
  for f in "$d"/*; do
    [ -f "$f" ] || continue
    b=$(basename "$f")
    b=${b%.agent.md}
    b=${b%.md}
    printf 'A\t%s\n' "$b"
  done
}

# Walk up from cwd for <bundle>/config.yaml. Prints the path, or returns 1.
te_discover_config() {
  local bundle_name dir
  bundle_name=$(basename "$TE_BUNDLE")
  dir=$PWD
  while :; do
    if [ -f "$dir/$bundle_name/config.yaml" ]; then
      printf '%s\n' "$dir/$bundle_name/config.yaml"
      return 0
    fi
    [ "$dir" = "/" ] && break
    dir=$(dirname "$dir")
  done
  return 1
}

# Print the where/completed/failed/recovery failure shape to stdout. Callers
# exit 1 after. `completed` is optional (repeatable via a newline-joined $4).
te_emit_fail() {
  local where=$1 failed=$2 recovery=$3 completed=${4:-}
  printf 'ok=false\nwhere=%s\n' "$where"
  if [ -n "$completed" ]; then
    printf '%s\n' "$completed" | while IFS= read -r line; do
      [ -n "$line" ] && printf 'completed=%s\n' "$line"
    done
  fi
  printf 'failed=%s\nrecovery=%s\n' "$failed" "$recovery"
}

# Internal error (a te bug or environment fault): stderr, exit 2.
te_internal() {
  printf 'ok=false\nwhere=internal\nfailed=%s\nrecovery=%s\n' \
    "$1" "${2:-report this as a te bug}" >&2
  exit 2
}

# resolve_config [path] — discover/parse/validate and print the flat resolved
# config on stdout (rc 0). On any discovery/parse/validation failure, print the
# ok=false shape on stdout and return 1. Requires TE_TMPD (set up by main).
# The bundle name in messages is derived, since te is byte-identical across the
# .claude and .agents copies.
resolve_config() {
  local cfg="${1:-}" bundle flat err combined out rc
  bundle=$(basename "$TE_BUNDLE")
  if [ -z "$cfg" ]; then
    if ! cfg=$(te_discover_config); then
      te_emit_fail "discovery" \
        "No $bundle/config.yaml found between $PWD and /." \
        "Run /ticket:init to bootstrap one, or pass the config path explicitly."
      return 1
    fi
  fi
  if [ ! -f "$cfg" ]; then
    te_emit_fail "discovery" "config file not found: $cfg" "check the path, or run /ticket:init"
    return 1
  fi
  flat="$TE_TMPD/flat"; err="$TE_TMPD/err"; combined="$TE_TMPD/combined"
  set +e
  awk -f "$TE_LIB/config.awk" -v path="$cfg" "$cfg" >"$flat" 2>"$err"; rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    te_emit_fail "parse" "$(cat "$err")" \
      "fix the YAML at the pointed line — it drifted outside the supported subset — or re-run /ticket:init"
    return 1
  fi
  cat "$flat" >"$combined"
  te_agent_records "$(dirname "$cfg")/agents" >>"$combined"
  set +e
  out=$(awk -f "$TE_LIB/validate.awk" -v path="$cfg" "$combined"); rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    te_emit_fail "validation" "$out" \
      "fix ${cfg} per the message, then re-run — the engine never proceeds past a config error"
    return 1
  fi
  printf '%s\n' "$out"
}

# cfg_get <key> — print the value of a resolved-config leaf (from
# $TE_TMPD/resolved); return 1 if the key is absent. Values may contain '='.
# Pure bash (the "no embedded awk" rule keeps every awk program in an -f file).
cfg_get() {
  local k="$1" line
  while IFS= read -r line; do
    case "$line" in
      "$k="*) printf '%s\n' "${line#*=}"; return 0 ;;
    esac
  done < "$TE_TMPD/resolved"
  return 1
}

# cfg_has <key> — true if the key exists as a leaf or a list/map prefix.
cfg_has() {
  local k="$1" line
  while IFS= read -r line; do
    case "$line" in
      "$k="*|"$k".*) return 0 ;;
    esac
  done < "$TE_TMPD/resolved"
  return 1
}
