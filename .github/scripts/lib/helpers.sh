# helpers.sh — side-effect-free ticket primitives for te (TE-002). Sourced by
# te; not executable. bash 3.2 clean. The awk pieces live in lib/*.awk or as
# ENVIRON-fed one-liners so shell quoting never touches user data.

# --- te slug "<title>" -------------------------------------------------------
# § Slug generation: lowercase, keep [a-z0-9 ], collapse whitespace, first 6
# words, join with '-'. Worked example:
#   "Add bee hive node for honey production" -> "add-bee-hive-node-for-honey"
cmd_slug() {
  local title="${1:-}"
  if [ -z "$title" ]; then
    te_emit_fail "slug" "no title given" 'usage: te slug "<title>"'
    return 1
  fi
  local words w out="" i=0
  # lowercase, then map every char outside [a-z0-9] to a space; word-split.
  words=$(printf '%s' "$title" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -c 'a-z0-9' ' ')
  # shellcheck disable=SC2086  # intentional word-split on whitespace
  set -- $words
  for w in "$@"; do
    [ "$i" -ge 6 ] && break
    out="${out:+$out-}$w"
    i=$((i + 1))
  done
  if [ -z "$out" ]; then
    te_emit_fail "slug" "title '$title' has no slug-able characters" \
      "give a title containing letters or digits"
    return 1
  fi
  printf '%s\n' "$out"
}

# --- te effort-cap --effort <e> --role <r> [config] --------------------------
# § Effort caps: a stage carrying the `pickable` role requires
# effort ∈ effort.pickable_allowed. No enforcement on other roles.
cmd_effort_cap() {
  local effort="" role="" cfg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --effort) effort="${2:-}"; shift 2 ;;
      --role)   role="${2:-}";   shift 2 ;;
      --dry-run) shift ;;
      *) cfg="$1"; shift ;;
    esac
  done
  if [ -z "$effort" ] || [ -z "$role" ]; then
    te_emit_fail "effort-cap" "both --effort and --role are required" \
      "usage: te effort-cap --effort <e> --role <r>"
    return 1
  fi
  load_config "$cfg" || return 1
  if [ "$role" != "pickable" ]; then echo "ok=true"; return 0; fi
  local i=0 v list="" found=0
  while v=$(cfg_get "effort.pickable_allowed.$i"); do
    list="${list:+$list, }$v"
    [ "$v" = "$effort" ] && found=1
    i=$((i + 1))
  done
  if [ "$found" -eq 1 ]; then
    echo "ok=true"
  else
    te_emit_fail "effort-cap" \
      "effort $effort not allowed in pickable stage; allowed: $list" \
      "split the ticket or rescope"
    return 1
  fi
}

# --- filesystem scan helpers -------------------------------------------------
# Each folder to scan for tickets: every stage folder, plus the milestone
# tracker folders when the strategy resolves to `trackers` (auto -> trackers on
# filesystem). All relative to backend.filesystem.root.
_fs_scan_folders() {
  local root strat i folder pa sh
  root=$(cfg_get backend.filesystem.root)
  i=0
  while folder=$(cfg_get "lifecycle.stages.$i.filesystem.folder"); do
    printf '%s/%s\n' "$root" "$folder"
    i=$((i + 1))
  done
  strat=$(cfg_get milestones.strategy || true)
  if [ "$strat" = "trackers" ] || [ "$strat" = "auto" ]; then
    pa=$(cfg_get milestones.trackers.planned_active_folder || echo milestone)
    sh=$(cfg_get milestones.trackers.shipped_folder || echo done)
    printf '%s/%s\n' "$root" "$pa"
    printf '%s/%s\n' "$root" "$sh"
  fi
}

# Every ticket ID present as a file across the scan folders (id = the
# {prefix}-{NNN} half of {prefix}-{NNN}-{slug}.md).
_fs_ticket_ids() {
  local prefix folder f base num
  prefix=$(cfg_get ticket_id.prefix)
  while IFS= read -r folder; do
    [ -d "$folder" ] || continue
    for f in "$folder/$prefix"-*.md; do
      [ -f "$f" ] || continue
      base=$(basename "$f")
      num=${base#"$prefix"-}
      num=${num%%-*}
      num=${num%.md}
      case "$num" in ''|*[!0-9]*) continue ;; esac
      printf '%s-%s\n' "$prefix" "$num"
    done
  done < <(_fs_scan_folders)
}

_ledger_path() { printf '%s/.ledger.yaml\n' "$(cfg_get backend.filesystem.root)"; }

# Flatten the ledger at $1 into $TE_TMPD/ledger (config.awk records). On a parse
# error, emit the failure shape and return 1. On a missing file, leave an empty
# records file and return 0.
_ledger_flatten() {
  local lp="$1" err rc
  : > "$TE_TMPD/ledger"
  [ -f "$lp" ] || return 0
  err="$TE_TMPD/lerr"
  set +e
  awk -f "$TE_LIB/config.awk" -v path="$lp" "$lp" >"$TE_TMPD/ledger" 2>"$err"; rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    te_emit_fail "parse" "$(cat "$err")" "fix $lp at the pointed line — the ledger drifted outside the supported subset"
    return 1
  fi
}

# Top-level ledger entry IDs (T records with no dot in the key).
_ledger_entries() {
  local tag key rest
  while IFS="$(printf '\t')" read -r tag key rest; do
    [ "$tag" = "T" ] || continue
    case "$key" in *.*) ;; *) printf '%s\n' "$key" ;; esac
  done < "$TE_TMPD/ledger"
}

# src<TAB>field<TAB>ref for every depends_on/related reference in the ledger.
_ledger_refs() {
  local tag key val rest
  while IFS="$(printf '\t')" read -r tag key val rest; do
    [ "$tag" = "V" ] || continue
    case "$key" in
      *.depends_on.*) printf '%s\tdepends_on\t%s\n' "${key%%.depends_on.*}" "$val" ;;
      *.related.*)    printf '%s\trelated\t%s\n'    "${key%%.related.*}"    "$val" ;;
    esac
  done < "$TE_TMPD/ledger"
}

# id<TAB>dep for every depends_on edge (the graph deps.awk walks).
_ledger_edges() {
  local tag key val rest
  while IFS="$(printf '\t')" read -r tag key val rest; do
    [ "$tag" = "V" ] || continue
    case "$key" in *.depends_on.*) printf '%s\t%s\n' "${key%%.depends_on.*}" "$val" ;; esac
  done < "$TE_TMPD/ledger"
}

# --- te id next [--count N] [config] -----------------------------------------
# § ID assignment (filesystem): max+1 across every scan folder, zero-padded and
# prefixed; N consecutive. On the github backend, provisional NEW-1 … NEW-N.
cmd_id_next() {
  local count=1 cfg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --count) count="${2:-}"; shift 2 ;;
      --dry-run) shift ;;
      *) cfg="$1"; shift ;;
    esac
  done
  case "$count" in ''|*[!0-9]*|0) te_emit_fail "id-next" "--count must be a positive integer, got '$count'" "pass --count N with N>=1"; return 1 ;; esac
  load_config "$cfg" || return 1
  local backend k; backend=$(cfg_get backend.type)
  if [ "$backend" = "github" ]; then
    k=1; while [ "$k" -le "$count" ]; do echo "NEW-$k"; k=$((k + 1)); done
    return 0
  fi
  local prefix padding max=0 id num next
  prefix=$(cfg_get ticket_id.prefix)
  padding=$(cfg_get ticket_id.padding)
  while IFS= read -r id; do
    num=${id#"$prefix"-}
    num=$((10#$num))
    [ "$num" -gt "$max" ] && max=$num
  done < <(_fs_ticket_ids)
  k=1
  while [ "$k" -le "$count" ]; do
    next=$((max + k))
    printf "%s-%0${padding}d\n" "$prefix" "$next"
    k=$((k + 1))
  done
}

# --- te deps check <id> --depends-on <ids> [--slate <ids>] [config] ----------
# § depends_on integrity (filesystem). Existence (ticket file OR ledger entry;
# slate IDs exempt) + a cycle walk reporting the full chain. Never follows
# related. The github graph source is TE-004; the walk is shared (deps.awk).
cmd_deps_check() {
  local id="" deps="" slate="" cfg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --depends-on) deps="${2:-}"; shift 2 ;;
      --slate) slate="${2:-}"; shift 2 ;;
      --dry-run) shift ;;
      *) if [ -z "$id" ]; then id="$1"; else cfg="$1"; fi; shift ;;
    esac
  done
  if [ -z "$id" ]; then
    te_emit_fail "deps-check" "no ticket id given" "usage: te deps check <id> --depends-on <ids>"
    return 1
  fi
  load_config "$cfg" || return 1
  local backend; backend=$(cfg_get backend.type)
  if [ "$backend" != "filesystem" ]; then
    echo "ok=true"; echo "note=deps check on the $backend backend lands in TE-004 (graph source differs; the walk is shared)"
    return 0
  fi
  _ledger_flatten "$(_ledger_path)" || return 1
  deps=$(printf '%s' "$deps" | tr ',' ' ')
  slate=$(printf '%s' "$slate" | tr ',' ' ')
  _fs_ticket_ids | sort -u > "$TE_TMPD/fileids"
  _ledger_entries | sort -u > "$TE_TMPD/entries"
  cat "$TE_TMPD/fileids" "$TE_TMPD/entries" | sort -u > "$TE_TMPD/known"
  local dep
  for dep in $deps; do
    [ -n "$dep" ] || continue
    case " $slate " in *" $dep "*) continue ;; esac
    if ! grep -Fxq "$dep" "$TE_TMPD/known"; then
      te_emit_fail "deps-check" "depends_on references $dep, which does not exist" \
        "fix the ID or drop the dependency"
      return 1
    fi
  done
  { _ledger_edges; for dep in $deps; do [ -n "$dep" ] && printf '%s\t%s\n' "$id" "$dep"; done; } > "$TE_TMPD/edges"
  local chain rc
  set +e
  chain=$(awk -f "$TE_LIB/deps.awk" -v start="$id" "$TE_TMPD/edges"); rc=$?
  set -e
  # deps.awk exits 2 with the chain on a cycle; a fatal awk error also exits 2
  # but prints nothing to stdout, so a non-empty chain disambiguates the two.
  if [ "$rc" -eq 2 ] && [ -n "$chain" ]; then
    te_emit_fail "deps-check" "depends_on cycle: $chain" "break the cycle by dropping one of the links"
    return 1
  elif [ "$rc" -ne 0 ]; then
    te_internal "deps.awk failed (exit $rc) while walking the dependency graph"
  fi
  echo "ok=true"
}

# --- te ledger validate [config] ---------------------------------------------
# § Ledger validation-on-load. Standalone (NOT folded into config validate);
# load_and_validate() calls both in sequence. Missing ledger -> soft warning.
cmd_ledger_validate() {
  local cfg=""
  while [ $# -gt 0 ]; do case "$1" in --dry-run) shift ;; *) cfg="$1"; shift ;; esac; done
  load_config "$cfg" || return 1
  local backend; backend=$(cfg_get backend.type)
  if [ "$backend" != "filesystem" ]; then
    echo "ok=true"; echo "note=ledger is filesystem-only; nothing to validate on the $backend backend"
    return 0
  fi
  local lp; lp=$(_ledger_path)
  if [ ! -f "$lp" ]; then
    echo "ok=true"; echo "warning=no .ledger.yaml at $lp; treated as empty (run /ticket:init to create the stub)"
    return 0
  fi
  _ledger_flatten "$lp" || return 1
  _fs_ticket_ids | sort -u > "$TE_TMPD/fileids"
  _ledger_entries | sort -u > "$TE_TMPD/entries"
  local e
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    if ! grep -Fxq "$e" "$TE_TMPD/fileids"; then
      te_emit_fail "ledger" "ledger entry '$e' resolves to no ticket file" \
        "remove the stale entry, or restore the ticket file"
      return 1
    fi
  done < "$TE_TMPD/entries"
  cat "$TE_TMPD/fileids" "$TE_TMPD/entries" | sort -u > "$TE_TMPD/known"
  local src field ref
  while IFS="$(printf '\t')" read -r src field ref; do
    if ! grep -Fxq "$ref" "$TE_TMPD/known"; then
      te_emit_fail "ledger" "$src: $field '$ref' resolves to no ticket file and no ledger entry" \
        "fix the reference or drop it"
      return 1
    fi
  done < <(_ledger_refs)
  local chain rc
  set +e
  chain=$(_ledger_edges | awk -f "$TE_LIB/deps.awk"); rc=$?
  set -e
  if [ "$rc" -eq 2 ] && [ -n "$chain" ]; then
    te_emit_fail "ledger" "depends_on cycle: $chain" "break the cycle by dropping one of the links"
    return 1
  elif [ "$rc" -ne 0 ]; then
    te_internal "deps.awk failed (exit $rc) while walking the ledger graph"
  fi
  echo "ok=true"
}

# --- te validate-body --type <t> --file <path> [config] ----------------------
# validate_type_body(): required sections present as headings; known-type
# non-empty rules (feature->acceptance_criteria, bug->regression_test).
cmd_validate_body() {
  local type="" file="" cfg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --type) type="${2:-}"; shift 2 ;;
      --file) file="${2:-}"; shift 2 ;;
      --dry-run) shift ;;
      *) cfg="$1"; shift ;;
    esac
  done
  if [ -z "$type" ] || [ -z "$file" ]; then
    te_emit_fail "validate-body" "both --type and --file are required" \
      "usage: te validate-body --type <t> --file <path>"
    return 1
  fi
  if [ ! -f "$file" ]; then
    te_emit_fail "validate-body" "body file not found: $file" "check the path"
    return 1
  fi
  load_config "$cfg" || return 1
  if ! cfg_has "types.$type"; then
    te_emit_fail "validate-body" "unknown type '$type'" "declare it under types:, or use a known type"
    return 1
  fi
  local req="" i=0 v ne=""
  while v=$(cfg_get "types.$type.required_body_sections.$i"); do
    req="${req:+$req,}$v"; i=$((i + 1))
  done
  case "$type" in
    feature) ne="acceptance_criteria" ;;
    bug)     ne="regression_test" ;;
  esac
  local out rc
  set +e
  out=$(awk -f "$TE_LIB/body.awk" -v req="$req" -v nonempty="$ne" "$file"); rc=$?
  set -e
  printf '%s\n' "$out"
  return "$rc"
}

# --- te msg <event> --id .. --title .. [flags] [config] ----------------------
# § Message formatting: interpolate the commits.<event> template. Hostile title
# characters survive via ENVIRON + msg.awk's single-pass render.
cmd_msg() {
  local event="" id="" title="" target="" status="" version="" reason="" cfg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --id) id="${2:-}"; shift 2 ;;
      --title) title="${2:-}"; shift 2 ;;
      --target-id) target="${2:-}"; shift 2 ;;
      --status) status="${2:-}"; shift 2 ;;
      --version) version="${2:-}"; shift 2 ;;
      --reason) reason="${2:-}"; shift 2 ;;
      --dry-run) shift ;;
      *) if [ -z "$event" ]; then event="$1"; else cfg="$1"; fi; shift ;;
    esac
  done
  if [ -z "$event" ]; then
    te_emit_fail "msg" "no event given" "usage: te msg <event> --id <id> --title <title>"
    return 1
  fi
  load_config "$cfg" || return 1
  local tmpl
  if ! tmpl=$(cfg_get "commits.$event"); then
    te_emit_fail "msg" "unknown event '$event' (no commits.$event template)" \
      "add the event under commits:, or check the name"
    return 1
  fi
  TE_MSG_TMPL="$tmpl" TE_MSG_id="$id" TE_MSG_title="$title" TE_MSG_target_id="$target" \
  TE_MSG_status="$status" TE_MSG_version="$version" TE_MSG_reason="$reason" \
    awk -f "$TE_LIB/msg.awk"
}
