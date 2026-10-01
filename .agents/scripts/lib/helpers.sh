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
# True if the ledger is effectively empty: only comments/blanks and/or the `{}`
# empty-map stub /ticket:init writes. config.awk rejects flow maps, so this is
# short-circuited rather than parsed.
_ledger_is_empty() {
  local line t
  while IFS= read -r line; do
    t=${line#"${line%%[![:space:]]*}"}      # lstrip
    t=${t%"${t##*[![:space:]]}"}            # rstrip
    case "$t" in ''|'#'*|'{}') ;; *) return 1 ;; esac
  done < "$1"
  return 0
}

_ledger_flatten() {
  local lp="$1" err rc
  : > "$TE_TMPD/ledger"
  [ -f "$lp" ] || return 0
  _ledger_is_empty "$lp" && return 0
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
  if [ "$backend" = "github" ]; then cmd_deps_check_gh "$id" "$deps" "$slate"; return; fi
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

# ---- setup manifest (<bundle>/setup/manifest.yaml) ---------------------------
# Walk up from cwd for <bundle>/setup/manifest.yaml. Prints the path, or rc 1.
te_discover_manifest() {
  local bundle_name dir
  bundle_name=$(basename "$TE_BUNDLE")
  dir=$PWD
  while :; do
    if [ -f "$dir/$bundle_name/setup/manifest.yaml" ]; then
      printf '%s\n' "$dir/$bundle_name/setup/manifest.yaml"
      return 0
    fi
    [ "$dir" = "/" ] && break
    dir=$(dirname "$dir")
  done
  return 1
}

# te manifest validate [path] — parse with config.awk (same YAML subset), then
# apply manifest.awk's rules. Read-only.
cmd_manifest_validate() {
  local mf="" bundle rc out
  while [ $# -gt 0 ]; do case "$1" in --dry-run) shift ;; *) mf="$1"; shift ;; esac; done
  bundle=$(basename "$TE_BUNDLE")
  if [ -z "$mf" ]; then
    if ! mf=$(te_discover_manifest); then
      te_emit_fail "discovery" "No $bundle/setup/manifest.yaml found between $PWD and /." \
        "Run /ticket:init — it writes the manifest beside config.yaml — or pass the path explicitly."
      return 1
    fi
  fi
  if [ ! -f "$mf" ]; then
    te_emit_fail "discovery" "manifest not found: $mf" "check the path, or run /ticket:init"
    return 1
  fi
  set +e
  awk -f "$TE_LIB/config.awk" -v path="$mf" "$mf" >"$TE_TMPD/mflat" 2>"$TE_TMPD/merr"; rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    te_emit_fail "parse" "$(cat "$TE_TMPD/merr")" \
      "the manifest is machine-owned — re-run /ticket:init (update mode) to rewrite it rather than hand-fixing"
    return 1
  fi
  local k
  for k in "$(te_kinds_dir)"/*.md; do
    [ -f "$k" ] || continue
    k=$(basename "$k"); printf 'K\t%s\n' "${k%.md}"
  done >>"$TE_TMPD/mflat"
  set +e
  out=$(awk -f "$TE_LIB/manifest.awk" "$TE_TMPD/mflat"); rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    te_emit_fail "manifest" "$out" \
      "the manifest is machine-owned — re-run /ticket:init (update mode) to rewrite it rather than hand-fixing"
    return 1
  fi
  printf '%s\n' "$out"
}

# ---- generated agents (references/agents/anatomy.md) ------------------------
# The agent kinds live beside te, in the same bundle: <bundle>/references/agents/kinds.
te_kinds_dir() { printf '%s\n' "$TE_BUNDLE/references/agents/kinds"; }

# _agent_parse <file> <outdir> — agent.awk records to <outdir>/recs; rc 1 + the
# failure shape on a structural error.
_agent_parse() {
  local f=$1 d=$2 rc
  rm -rf "$d"; mkdir -p "$d"   # never let a previous parse's region files leak in
  set +e
  awk -f "$TE_LIB/agent.awk" -v outdir="$d" "$f" >"$d/recs"; rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    local msg; msg=$(grep '^E' "$d/recs" | head -1 | cut -f2-)
    te_emit_fail "agent" "$f: ${msg:-could not parse}" \
      "regenerate the file from its kind (/ticket:init update mode), or repair the markers by hand — see references/agents/anatomy.md"
    return 1
  fi
}

# _rec <recs> <tag> <field2> — print field 3 of the first matching record.
_rec() {
  local line t a b
  while IFS="$(printf '\t')" read -r t a b; do
    if [ "$t" = "$2" ] && [ "$a" = "$3" ]; then printf '%s\n' "$b"; return 0; fi
  done < "$1"
  return 1
}

# _regions <recs> <type> — the ids of every region of that type, in order.
_regions() {
  local t a b
  while IFS="$(printf '\t')" read -r t a b; do
    [ "$t" = "R" ] && [ "$a" = "$2" ] && printf '%s\n' "$b"
  done < "$1"
  return 0
}

_hash() { local c s; read -r c s _ < <(cksum < "$1"); printf '%s-%s\n' "$c" "$s"; }

# te agent check <file> [--kind K] — anatomy + contract conformance. Read-only.
cmd_agent_check() {
  local f="" want="" stem name desc kind kf kd ad id gen t a
  while [ $# -gt 0 ]; do
    case "$1" in
      --kind) want="$2"; shift 2 ;;
      --dry-run) shift ;;
      *) f="$1"; shift ;;
    esac
  done
  [ -n "$f" ] || { te_emit_fail "agent" "no agent file given" "te agent check <file> [--kind K]"; return 1; }
  [ -f "$f" ] || { te_emit_fail "agent" "agent file not found: $f" "check the path"; return 1; }
  ad="$TE_TMPD/agent"; kd="$TE_TMPD/kind"
  _agent_parse "$f" "$ad" || return 1

  stem=$(basename "$f"); stem=${stem%.agent.md}; stem=${stem%.md}
  name=$(_rec "$ad/recs" FM name || true)
  desc=$(_rec "$ad/recs" FM description || true)
  if [ "$name" != "$stem" ]; then
    te_emit_fail "agent" "$f: frontmatter name '${name}' must equal the file stem '$stem' — assistants dispatch by name" "fix the name or rename the file"
    return 1
  fi
  if [ -z "$desc" ]; then
    te_emit_fail "agent" "$f: frontmatter description is empty — it is what an assistant reads to decide when to delegate" "write a one-sentence description naming what the agent does and when it is invoked"
    return 1
  fi
  # the bundle's agent line: Claude Code grants tools from `tools:`; Antigravity
  # discovers subagents only by `subagent: true`.
  case "$(basename "$TE_BUNDLE")" in
    .agents)
      if [ "$(_rec "$ad/recs" FM subagent || true)" != "true" ]; then
        te_emit_fail "agent" "$f: frontmatter lacks 'subagent: true' — Antigravity's invoke_subagent will not see it" "add 'subagent: true' to the frontmatter"
        return 1
      fi ;;
    *)
      if [ -z "$(_rec "$ad/recs" FM tools || true)" ]; then
        te_emit_fail "agent" "$f: frontmatter lacks a 'tools:' line — the subagent would inherit every tool" "add the kind's tools line"
        return 1
      fi ;;
  esac
  kind=""
  while IFS="$(printf '\t')" read -r t a _; do [ "$t" = KIND ] && kind=$a; done < "$ad/recs"
  if [ -z "$kind" ]; then
    te_emit_fail "agent" "$f: no <!-- agent-kind: <kind> --> marker after the frontmatter" "add the marker naming the kind the agent was generated from"
    return 1
  fi
  if [ -n "$want" ] && [ "$want" != "$kind" ]; then
    te_emit_fail "agent" "$f: agent-kind is '$kind', expected '$want'" "regenerate the agent from the '$want' kind"
    return 1
  fi
  kf="$(te_kinds_dir)/$kind.md"
  if [ ! -f "$kf" ]; then
    te_emit_fail "agent" "$f: unknown agent kind '$kind' (no $(basename "$TE_BUNDLE")/references/agents/kinds/$kind.md)" "use one of: $(ls "$(te_kinds_dir)" 2>/dev/null | sed 's/\.md$//' | tr '\n' ' ')"
    return 1
  fi
  _agent_parse "$kf" "$kd" || return 1

  # contract regions: exactly the kind's set, byte-identical
  for id in $(_regions "$kd/recs" contract); do
    if [ ! -f "$ad/contract.$id" ]; then
      te_emit_fail "agent" "$f: missing contract region '$id' required by kind '$kind'" "copy it verbatim from: te agent contract $kind"
      return 1
    fi
    if ! cmp -s "$ad/contract.$id" "$kd/contract.$id"; then
      te_emit_fail "agent" "$f: contract region '$id' differs from kind '$kind' — contract regions are copied verbatim, never edited" "replace the region with the output of: te agent contract $kind"
      return 1
    fi
  done
  for id in $(_regions "$ad/recs" contract); do
    if [ ! -f "$kd/contract.$id" ]; then
      te_emit_fail "agent" "$f: contract region '$id' is not part of kind '$kind'" "remove it — only the kind defines contract regions"
      return 1
    fi
  done
  # generated regions: exactly the ids the kind declares
  gen=$(_rec "$kd/recs" FM regions || true)
  for id in $gen; do
    if [ ! -f "$ad/generated.$id" ]; then
      te_emit_fail "agent" "$f: missing generated region '$id' (kind '$kind' declares: $gen)" "generate it per the kind's guidance"
      return 1
    fi
  done
  for id in $(_regions "$ad/recs" generated); do
    case " $gen " in *" $id "*) ;; *)
      te_emit_fail "agent" "$f: generated region '$id' is not declared by kind '$kind' (declares: $gen)" "rename it to a declared region, or move project-owned text into the user region"
      return 1 ;;
    esac
  done
  if [ ! -f "$ad/user.user" ]; then
    te_emit_fail "agent" "$f: no <!-- user:start --> … <!-- user:end --> region" "add the (possibly empty) user region — it is the one place init never rewrites"
    return 1
  fi

  printf 'ok=true\nname=%s\nkind=%s\n' "$name" "$kind"
  for id in $(_regions "$ad/recs" generated); do printf 'hash.%s=%s\n' "$id" "$(_hash "$ad/generated.$id")"; done
  printf 'hash.user=%s\n' "$(_hash "$ad/user.user")"
}

# te agent contract <kind> — print the kind's contract regions, markers included,
# exactly as a generated agent must carry them. Read-only.
cmd_agent_contract() {
  local kind="${1:-}" kf kd id
  [ -n "$kind" ] || { te_emit_fail "agent" "no kind given" "te agent contract <kind>"; return 1; }
  kf="$(te_kinds_dir)/$kind.md"
  [ -f "$kf" ] || { te_emit_fail "agent" "unknown agent kind '$kind' (no $(basename "$TE_BUNDLE")/references/agents/kinds/$kind.md)" "use one of: $(ls "$(te_kinds_dir)" 2>/dev/null | sed 's/\.md$//' | tr '\n' ' ')"; return 1; }
  kd="$TE_TMPD/kind"
  _agent_parse "$kf" "$kd" || return 1
  for id in $(_regions "$kd/recs" contract); do
    printf '<!-- contract:start id=%s -->\n' "$id"
    cat "$kd/contract.$id"
    printf '<!-- contract:end id=%s -->\n\n' "$id"
  done
}

# te agent reply-check (--kind K | --agent NAME) <reply-file> — the light check a
# caller runs on a subagent's reply before trusting it: exactly one
# `**<label>:** <value>` line whose value matches one of the kind's verdicts
# (glob patterns, `; `-separated), and a line matching each required heading.
# A hand-written agent (no agent-kind marker) has no contract: ok, unchecked.
cmd_agent_reply_check() {
  local kind="" agent="" rf="" af kf kd label verdicts headings n v pat matched line IFS_SAVE
  while [ $# -gt 0 ]; do
    case "$1" in
      --kind) kind="$2"; shift 2 ;;
      --agent) agent="$2"; shift 2 ;;
      --dry-run) shift ;;
      *) rf="$1"; shift ;;
    esac
  done
  [ -n "$rf" ] && [ -f "$rf" ] || { te_emit_fail "reply" "reply file not found: ${rf:-<none>}" "save the agent's reply to a file and pass its path"; return 1; }
  if [ -z "$kind" ]; then
    [ -n "$agent" ] || { te_emit_fail "reply" "pass --kind K or --agent NAME" "te agent reply-check --agent code-reviewer reply.md"; return 1; }
    af="$TE_BUNDLE/agents/$agent.md"
    [ -f "$af" ] || { te_emit_fail "reply" "no agent file for '$agent' in $(basename "$TE_BUNDLE")/agents/" "check the name"; return 1; }
    _agent_parse "$af" "$TE_TMPD/ragent" || return 1
    while IFS="$(printf '\t')" read -r t a _; do [ "$t" = KIND ] && kind=$a; done < "$TE_TMPD/ragent/recs"
    if [ -z "$kind" ]; then
      printf 'ok=true\nchecked=false\nnote=%s is hand-written (no agent-kind marker); its reply has no contract to check\n' "$agent"
      return 0
    fi
  fi
  kf="$(te_kinds_dir)/$kind.md"
  [ -f "$kf" ] || { te_emit_fail "reply" "unknown agent kind '$kind' (no $(basename "$TE_BUNDLE")/references/agents/kinds/$kind.md)" "check the kind"; return 1; }
  kd="$TE_TMPD/rkind"
  _agent_parse "$kf" "$kd" || return 1
  label=$(_rec "$kd/recs" FM reply_label || true)
  verdicts=$(_rec "$kd/recs" FM reply_verdicts || true)
  headings=$(_rec "$kd/recs" FM reply_headings || true)
  [ -n "$label" ] && [ -n "$verdicts" ] || { te_emit_fail "reply" "kind '$kind' declares no reply_label/reply_verdicts" "add them to the kind's frontmatter"; return 1; }

  n=0; v=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "**$label:** "*) n=$((n + 1)); v=${line#"**$label:** "} ;;
    esac
  done < "$rf"
  v=$(printf '%s' "$v" | sed -e 's/[[:space:]]*$//')
  if [ "$n" -ne 1 ]; then
    te_emit_fail "reply" "expected exactly one '**$label:** <verdict>' line, found $n" \
      "re-ask the agent once, quoting this message and its output contract; on a second failure treat the agent as failed"
    return 1
  fi
  matched=0
  IFS_SAVE=$IFS; IFS=';'
  for pat in $verdicts; do
    pat=${pat# }; pat=${pat% }
    # shellcheck disable=SC2254
    case "$v" in $pat) matched=1 ;; esac
  done
  IFS=$IFS_SAVE
  if [ "$matched" -ne 1 ]; then
    te_emit_fail "reply" "'**$label:** $v' is not one of: $verdicts" \
      "re-ask the agent once, quoting this message and its output contract; on a second failure treat the agent as failed"
    return 1
  fi
  IFS=';'
  for pat in $headings; do
    IFS=$IFS_SAVE
    pat=${pat# }; pat=${pat% }
    [ -n "$pat" ] || continue
    matched=0
    while IFS= read -r line || [ -n "$line" ]; do
      # shellcheck disable=SC2254
      case "$line" in $pat) matched=1; break ;; esac
    done < "$rf"
    if [ "$matched" -ne 1 ]; then
      te_emit_fail "reply" "no line matching '$pat' — the reply does not follow the $kind output contract" \
        "re-ask the agent once, quoting this message and its output contract; on a second failure treat the agent as failed"
      return 1
    fi
    IFS=';'
  done
  IFS=$IFS_SAVE
  printf 'ok=true\nchecked=true\nkind=%s\nverdict=%s\n' "$kind" "$v"
}

# te agent drift [manifest] — compare every generated agent the manifest records
# against the file on disk: region by region, `untouched` (hash unchanged),
# `edited` (the project changed it), `added`/`removed` (the kind's region set
# moved); per agent `ok`, `missing` (file deleted), or `invalid` (no longer a
# valid rendering — most often a contract region gone stale after a bundle
# upgrade). Read-only; update mode's input.
cmd_agent_drift() {
  local mf="" root i name path kind out rc line key val id rid seen_ids
  while [ $# -gt 0 ]; do case "$1" in --dry-run) shift ;; *) mf="$1"; shift ;; esac; done
  if [ -z "$mf" ]; then
    mf=$(te_discover_manifest) || { te_emit_fail "discovery" "No $(basename "$TE_BUNDLE")/setup/manifest.yaml found between $PWD and /." "Run /ticket:init first"; return 1; }
  fi
  [ -f "$mf" ] || { te_emit_fail "discovery" "manifest not found: $mf" "check the path"; return 1; }
  # <root>/<bundle>/setup/manifest.yaml -> <root>
  root=$(cd "$(dirname "$mf")/../.." && pwd)
  set +e
  awk -f "$TE_LIB/config.awk" -v path="$mf" "$mf" >"$TE_TMPD/dflat" 2>"$TE_TMPD/derr"; rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    te_emit_fail "parse" "$(cat "$TE_TMPD/derr")" "re-run /ticket:init (update mode) to rewrite the manifest"
    return 1
  fi
  # manifest leaves as key=value, for lookups
  : >"$TE_TMPD/dkv"
  while IFS="$(printf '\t')" read -r t key val _; do
    [ "$t" = V ] && printf '%s=%s\n' "$key" "$val" >>"$TE_TMPD/dkv"
  done <"$TE_TMPD/dflat"
  _dkv() { local l; while IFS= read -r l; do case "$l" in "$1="*) printf '%s\n' "${l#*=}"; return 0 ;; esac; done <"$TE_TMPD/dkv"; return 1; }

  echo "ok=true"
  i=0
  while name=$(_dkv "agents.$i.name"); do
    path=$(_dkv "agents.$i.path" || true); kind=$(_dkv "agents.$i.kind" || true)
    if [ ! -f "$root/$path" ]; then
      printf 'agent.%s=missing\n' "$name"; i=$((i + 1)); continue
    fi
    set +e
    out=$( cd "$root" && TE_TMPD="$TE_TMPD/d$i" && mkdir -p "$TE_TMPD" && cmd_agent_check "$path" --kind "$kind" ); rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
      printf 'agent.%s=invalid\n' "$name"
      printf '%s\n' "$out" | while IFS= read -r line; do
        case "$line" in failed=*) printf 'agent.%s.reason=%s\n' "$name" "${line#failed=}" ;; esac
      done
      i=$((i + 1)); continue
    fi
    printf 'agent.%s=ok\n' "$name"
    seen_ids=" "
    while IFS= read -r line; do
      case "$line" in
        hash.*=*)
          id=${line#hash.}; id=${id%%=*}; val=${line#*=}
          seen_ids="$seen_ids$id "
          if ! rid=$(_dkv "agents.$i.hashes.$id"); then
            printf 'region.%s.%s=added\n' "$name" "$id"
          elif [ "$rid" = "$val" ]; then
            printf 'region.%s.%s=untouched\n' "$name" "$id"
          else
            printf 'region.%s.%s=edited\n' "$name" "$id"
          fi ;;
      esac
    done <<<"$out"
    while IFS= read -r line; do
      case "$line" in
        "agents.$i.hashes."*=*)
          id=${line#"agents.$i.hashes."}; id=${id%%=*}
          case "$seen_ids" in *" $id "*) ;; *) printf 'region.%s.%s=removed\n' "$name" "$id" ;; esac ;;
      esac
    done <"$TE_TMPD/dkv"
    i=$((i + 1))
  done
  printf 'agents=%s\n' "$i"
}
