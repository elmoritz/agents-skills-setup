# common.sh — shared shell helpers for te. Sourced by te; not executable.
# bash 3.2 clean: no declare -A, no mapfile, no ${x,,}.
#
# Relies on TE_SELF (dir of the te entrypoint) and TE_BUNDLE (its parent, the
# bundle root — .claude or .github), both exported by te before sourcing.

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
