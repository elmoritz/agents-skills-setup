# read-gh.sh — the github read path (TE-004), conforming to TE-003's frozen
# field view. Reads render via `gh --template` (Go templates → flat key=value),
# never `gh --json` + awk. Sourced by te. bash 3.2 clean; all awk (deps.awk) via
# -f. Mapping is offline-testable via TE_GH_FIXTURE (see below).
#
# OFFLINE TEST SEAM: every gh call goes through a _gh_* fetch function. When
# TE_GH_FIXTURE is set, the fetch reads a recorded file instead of shelling to
# gh, so the mapping layer (flat gh output → field view) is tested with no gh and
# no network. The recorded fixtures under tests/fixtures/gh/ are HAND-AUTHORED to
# represent the templates' output — they are NOT captured from a live repo, so
# the live gh path and the Projects field/option resolution remain manually
# verified (see the ticket's Prerequisite + manual checklist). The templates are
# written defensively (nil guards, list ranges) so production never emits
# `<no value>` where the schema wants an empty field.

# --- gh --template strings (defensive: guarded for null, ranges for lists) ----
# Confirmed field shapes against live gh 2.96 (2026-07-27): `blockedBy` is a
# CONNECTION object `{nodes:[{number,...}], totalCount}` — range `.blockedBy.nodes`,
# never `.blockedBy` (ranging the object hits totalCount and errors, which aborts
# the whole template and truncates every later field). `labels`/`assignees` are
# flat arrays; `milestone`/`issueType` are objects-or-null (guarded with {{if}}).
# Flat key=value view of one issue, then the body after ---BODY---.
TE_GH_VIEW_TMPL='number={{.number}}
title={{.title}}
state={{.state}}
stateReason={{.stateReason}}
createdAt={{.createdAt}}
issueType={{if .issueType}}{{.issueType.name}}{{end}}
assignee={{range $i, $a := .assignees}}{{if $i}},{{end}}{{$a.login}}{{end}}
milestone={{if .milestone}}{{.milestone.title}}{{end}}
blockedBy={{if .blockedBy}}{{range $i, $b := .blockedBy.nodes}}{{if $i}},{{end}}{{$b.number}}{{end}}{{end}}
labels={{range $i, $l := .labels}}{{if $i}},{{end}}{{$l.name}}{{end}}
url={{.url}}
---BODY---
{{.body}}'

# One line per issue for lists: fields separated by US (\x1f, a non-whitespace
# delimiter — a tab-IFS read collapses consecutive tabs and would eat empty
# middle fields like an absent stateReason/assignee). Body excluded.
TE_GH_LIST_TMPL='{{range .}}{{.number}}{{"\x1f"}}{{.title}}{{"\x1f"}}{{.state}}{{"\x1f"}}{{.stateReason}}{{"\x1f"}}{{.createdAt}}{{"\x1f"}}{{if .issueType}}{{.issueType.name}}{{end}}{{"\x1f"}}{{range $i, $a := .assignees}}{{if $i}},{{end}}{{$a.login}}{{end}}{{"\x1f"}}{{if .milestone}}{{.milestone.title}}{{end}}{{"\x1f"}}{{if .blockedBy}}{{range $i, $b := .blockedBy.nodes}}{{if $i}},{{end}}{{$b.number}}{{end}}{{end}}{{"\x1f"}}{{range $i, $l := .labels}}{{if $i}},{{end}}{{$l.name}}{{end}}{{"\x1f"}}{{.url}}{{"\n"}}{{end}}'

# id<TAB>blockedBy-csv per issue, for the deps.awk edge list.
TE_GH_DEPS_TMPL='{{range .}}{{$n := .number}}{{if .blockedBy}}{{range .blockedBy.nodes}}{{$n}}{{"\t"}}{{.number}}{{"\n"}}{{end}}{{end}}{{end}}'

TE_GH_LIMIT=1000   # explicit high limit: gh list calls default to 30 rows, which
                   # would silently truncate the dependency graph / board join.
US=$(printf '\037') # unit separator: the field delimiter for multi-field rows

_gh_repo() { cfg_get backend.github.repo; }

_gh_owner() {  # owner half of owner/repo
  local r; r=$(_gh_repo); printf '%s\n' "${r%%/*}"
}

# gh >= 2.94 introduced the blockedBy JSON field. Below that, a silent empty
# would make --depends-satisfied wrongly pass every ticket, so hard-fail pointed.
_gh_version_ok() {
  [ -n "${TE_GH_FIXTURE:-}" ] && return 0   # offline: fixtures already have it
  local v major minor
  v=$(gh --version 2>/dev/null | head -1 | sed -E 's/[^0-9]*([0-9]+\.[0-9]+).*/\1/')
  major=${v%%.*}; minor=${v#*.}
  [ -n "$major" ] || return 1
  [ "$major" -gt 2 ] && return 0
  [ "$major" -eq 2 ] && [ "$minor" -ge 94 ] && return 0
  return 1
}

# --- fetch functions (fixture-backed when TE_GH_FIXTURE is set) ---------------
_gh_view() {  # $1 issue number -> raw view (template output)
  if [ -n "${TE_GH_FIXTURE:-}" ]; then cat "$TE_GH_FIXTURE/issue-$1.view" 2>/dev/null; return; fi
  gh issue view "$1" --repo "$(_gh_repo)" \
    --json number,title,state,stateReason,createdAt,issueType,assignees,milestone,blockedBy,labels,body,url \
    --template "$TE_GH_VIEW_TMPL"
}
_gh_timeline() {  # $1 issue number -> one `assigned` event timestamp per line
  if [ -n "${TE_GH_FIXTURE:-}" ]; then cat "$TE_GH_FIXTURE/issue-$1.timeline" 2>/dev/null; return; fi
  gh api "repos/$(_gh_repo)/issues/$1/timeline" --paginate \
    --template '{{range .}}{{if eq .event "assigned"}}{{.created_at}}{{"\n"}}{{end}}{{end}}'
}
_gh_list_raw() {  # $1 state (open|all) -> one TAB line per issue
  if [ -n "${TE_GH_FIXTURE:-}" ]; then cat "$TE_GH_FIXTURE/issue-list-$1.txt" 2>/dev/null; return; fi
  gh issue list --repo "$(_gh_repo)" --state "$1" --limit "$TE_GH_LIMIT" \
    --json number,title,state,stateReason,createdAt,issueType,assignees,milestone,blockedBy,labels,url \
    --template "$TE_GH_LIST_TMPL"
}
_gh_deps_raw() {  # id<TAB>dep edge list over all issues
  if [ -n "${TE_GH_FIXTURE:-}" ]; then cat "$TE_GH_FIXTURE/edges.txt" 2>/dev/null; return; fi
  gh issue list --repo "$(_gh_repo)" --state all --limit "$TE_GH_LIMIT" \
    --json number,blockedBy --template "$TE_GH_DEPS_TMPL"
}
_gh_project_items() {  # url<TAB>priority<TAB>effort<TAB>risk from the board
  if [ -n "${TE_GH_FIXTURE:-}" ]; then cat "$TE_GH_FIXTURE/project-items.txt" 2>/dev/null; return; fi
  local num owner; num=$(cfg_get projects.number); owner=$(cfg_get projects.owner)
  gh project item-list "$num" --owner "$owner" --limit "$TE_GH_LIMIT" --format json \
    --template '{{range .items}}{{if .content.url}}{{.content.url}}{{"\x1f"}}{{with .priority}}{{.name}}{{end}}{{"\x1f"}}{{with .effort}}{{.name}}{{end}}{{"\x1f"}}{{with .risk}}{{.name}}{{end}}{{"\n"}}{{end}}{{end}}'
}
_gh_milestones() {  # title<TAB>state<TAB>open<TAB>closed per milestone
  if [ -n "${TE_GH_FIXTURE:-}" ]; then cat "$TE_GH_FIXTURE/milestones.txt" 2>/dev/null; return; fi
  gh api "repos/$(_gh_repo)/milestones?state=all" --paginate \
    --template '{{range .}}{{.title}}{{"\t"}}{{.state}}{{"\t"}}{{.open_issues}}{{"\t"}}{{.closed_issues}}{{"\n"}}{{end}}'
}
_gh_fields_raw() {  # field-list json rows for projects resolve
  if [ -n "${TE_GH_FIXTURE:-}" ]; then cat "$TE_GH_FIXTURE/project-fields.txt" 2>/dev/null; return; fi
  local num owner; num=$(cfg_get projects.number); owner=$(cfg_get projects.owner)
  gh project field-list "$num" --owner "$owner" --format json \
    --template '{{range .fields}}{{.id}}{{"\t"}}{{.name}}{{"\t"}}{{.type}}{{"\n"}}{{end}}'
}

# --- mapping helpers ---------------------------------------------------------
# value of key=… line in a flat file ("" if absent)
_rawget() {
  local file=$1 k=$2 line
  while IFS= read -r line; do
    case "$line" in "$k="*) printf '%s\n' "${line#*=}"; return 0 ;; esac
  done < "$file"
  return 0
}
# suffix of the first CSV label starting with prefix $2 ("" if none)
_label_suffix() {
  local csv=$1 prefix=$2 IFS=, l
  for l in $csv; do
    case "$l" in "$prefix"*) printf '%s\n' "${l#"$prefix"}"; return 0 ;; esac
  done
  return 0
}
# stage key for a github issue: closed -> terminal stage key; else the stage
# whose github.label appears in the issue's labels. (Closed-state wins over a
# stale status label, so a closed issue always maps to the terminal key.)
_gh_stage_key() {
  local labels=$1 state=$2 i=0 skey glabel IFS=,
  if [ "$state" = "CLOSED" ]; then cfg_get roles.terminal; return 0; fi
  while skey=$(cfg_get "lifecycle.stages.$i.key"); do
    glabel=$(cfg_get "lifecycle.stages.$i.github.label" || true)
    if [ -n "$glabel" ]; then
      local l
      for l in $labels; do [ "$l" = "$glabel" ] && { printf '%s\n' "$skey"; return 0; }; done
    fi
    i=$((i + 1))
  done
  return 0
}
# reverse native issue type -> config type key via backend.github.type_map.
# The resolved config is key=value (not TAB) — split on the first '='.
_gh_type_from_native() {
  local native=$1 line kk vv
  [ -n "$native" ] || return 0
  while IFS= read -r line; do
    case "$line" in
      backend.github.type_map.*=*)
        kk=${line%%=*}; vv=${line#*=}
        [ "$vv" = "$native" ] && { printf '%s\n' "${kk#backend.github.type_map.}"; return 0; } ;;
    esac
  done < "$TE_TMPD/resolved"
  return 0
}
# closed_as from the native close reason (stateReason)
_gh_closed_as() {
  case "$1" in
    COMPLETED) printf 'shipped\n' ;;
    NOT_PLANNED) printf 'wontfix\n' ;;
    DUPLICATE) printf 'duplicate\n' ;;
  esac
  return 0
}
# board row for an issue url: "priority<TAB>effort<TAB>risk" ("" if not on board)
_gh_board_row() {
  local url=$1 c1 c2 c3 c4
  [ -f "$TE_TMPD/ghitems" ] || return 0
  while IFS="$US" read -r c1 c2 c3 c4; do
    [ "$c1" = "$url" ] && { printf '%s\t%s\t%s\n' "$c2" "$c3" "$c4"; return 0; }
  done < "$TE_TMPD/ghitems"
  return 0
}

# parse `Related: #12, #34` from a body file -> 12,34 (top-of-body line only)
_gh_related() {
  local bodyfile=$1 line out=""
  # `|| [ -n "$line" ]` processes a final line with no trailing newline — an
  # issue body's `Related:` line is often the last line and unterminated.
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      Related:*)
        line=${line#Related:}
        local IFS=, tok
        for tok in $line; do
          tok=${tok#"${tok%%[![:space:]]*}"}; tok=${tok#\#}
          tok=${tok%"${tok##*[![:space:]]}"}
          [ -n "$tok" ] && out="${out:+$out,}$tok"
        done
        printf '%s\n' "$out"; return 0 ;;
      '') continue ;;    # skip leading blanks
      *) return 0 ;;     # first non-blank, non-Related line -> no Related line
    esac
  done < "$bodyfile"
  return 0
}

# --- te read <id> (github) ---------------------------------------------------
cmd_read_gh() {
  local id=$1 rawv="$TE_TMPD/ghview"
  _gh_view "$id" > "$rawv"
  if [ ! -s "$rawv" ]; then printf 'ok=false\nreason=not found\n'; return 1; fi
  local sent fields="$TE_TMPD/ghfields" body="$TE_TMPD/ghbody"
  sent=$(grep -n '^---BODY---$' "$rawv" | head -1 | cut -d: -f1)
  if [ -n "$sent" ]; then
    sed -n "1,$((sent - 1))p" "$rawv" > "$fields"
    tail -n +"$((sent + 1))" "$rawv" > "$body"
  else
    cp "$rawv" "$fields"; : > "$body"
  fi
  local num title state stateReason createdAt itype assignee milestone blockedBy labels
  num=$(_rawget "$fields" number); title=$(_rawget "$fields" title)
  state=$(_rawget "$fields" state); stateReason=$(_rawget "$fields" stateReason)
  createdAt=$(_rawget "$fields" createdAt); itype=$(_rawget "$fields" issueType)
  assignee=$(_rawget "$fields" assignee); milestone=$(_rawget "$fields" milestone)
  blockedBy=$(_rawget "$fields" blockedBy); labels=$(_rawget "$fields" labels)

  local tp pr ef rk stage mil claimed_at related
  tp=$(_gh_type_from_native "$itype"); [ -n "$tp" ] || tp=$(_label_suffix "$labels" "type:")
  # dual-homed priority/effort/risk: board first (if enabled), else label
  pr=""; ef=""; rk=""
  if [ "$(cfg_get projects.enabled || true)" = "true" ]; then
    _gh_project_items > "$TE_TMPD/ghitems"
    local url row; url=$(_rawget "$fields" url); row=$(_gh_board_row "$url")
    if [ -n "$row" ]; then
      pr=$(printf '%s' "$row" | cut -f1); ef=$(printf '%s' "$row" | cut -f2); rk=$(printf '%s' "$row" | cut -f3)
    fi
  fi
  [ -n "$pr" ] || pr=$(_label_suffix "$labels" "prio:")
  [ -n "$ef" ] || ef=$(_label_suffix "$labels" "effort:")
  [ -n "$rk" ] || rk=$(_label_suffix "$labels" "risk:")
  stage=$(_gh_stage_key "$labels" "$state")
  # milestone: native title if present, else milestone: label
  mil="$milestone"; [ -n "$mil" ] || mil=$(_label_suffix "$labels" "milestone:")
  # claimed_at: latest assigned timeline event; empty if unassigned or no event
  claimed_at=""
  if [ -n "$assignee" ]; then claimed_at=$(_gh_timeline "$id" | grep -v '^$' | tail -1 || true); fi
  related=$(_gh_related "$body")

  printf 'id=%s\n' "$num"
  printf 'stage=%s\n' "$stage"
  printf 'type=%s\n' "$tp"
  printf 'title=%s\n' "$title"
  printf 'priority=%s\n' "$pr"
  printf 'effort=%s\n' "$ef"
  printf 'risk=%s\n' "$rk"
  printf 'milestone=%s\n' "$mil"
  printf 'created=%s\n' "$createdAt"
  printf 'claimed_by=%s\n' "$assignee"
  printf 'claimed_at=%s\n' "$claimed_at"
  printf 'closed_as=%s\n' "$(_gh_closed_as "$stateReason")"
  printf 'depends_on=%s\n' "$blockedBy"
  printf 'related=%s\n' "$related"
  printf '%s\n' "---BODY---"
  cat "$body"
  return 0
}

# --- te list <role> (github) -------------------------------------------------
cmd_list_gh() {
  local role=$1 f_priority=$2 f_effort=$3 f_type=$4 f_milestone=$5 depsat=$6
  local stagekey; stagekey=$(cfg_get "roles.$role" || true)
  if [ -z "$stagekey" ]; then
    te_emit_fail "list" "no stage carries the role '$role'" "check the role name"
    return 1
  fi
  local glabel="" i=0 skey
  while skey=$(cfg_get "lifecycle.stages.$i.key"); do
    [ "$skey" = "$stagekey" ] && glabel=$(cfg_get "lifecycle.stages.$i.github.label" || true)
    i=$((i + 1))
  done
  _gh_list_raw all > "$TE_TMPD/ghlist"
  local projects_on=""; [ "$(cfg_get projects.enabled || true)" = "true" ] && projects_on=1
  [ -n "$projects_on" ] && _gh_project_items > "$TE_TMPD/ghitems"
  # terminal detection: an issue is terminal iff CLOSED
  local first=1 num title state sr created itype assignee mil blockedBy labels url
  while IFS="$US" read -r num title state sr created itype assignee mil blockedBy labels url; do
    [ -n "$num" ] || continue
    local istage; istage=$(_gh_stage_key "$labels" "$state")
    [ "$istage" = "$stagekey" ] || continue
    local tp pr ef rk milv
    tp=$(_gh_type_from_native "$itype"); [ -n "$tp" ] || tp=$(_label_suffix "$labels" "type:")
    pr=""; ef=""; rk=""
    if [ -n "$projects_on" ]; then
      local brow; brow=$(_gh_board_row "$url")
      if [ -n "$brow" ]; then
        pr=$(printf '%s' "$brow" | cut -f1); ef=$(printf '%s' "$brow" | cut -f2); rk=$(printf '%s' "$brow" | cut -f3)
      fi
    fi
    [ -n "$pr" ] || pr=$(_label_suffix "$labels" "prio:")
    [ -n "$ef" ] || ef=$(_label_suffix "$labels" "effort:")
    [ -n "$rk" ] || rk=$(_label_suffix "$labels" "risk:")
    milv="$mil"; [ -n "$milv" ] || milv=$(_label_suffix "$labels" "milestone:")
    { [ -n "$f_priority" ] && [ "$f_priority" != "$pr" ]; } && continue
    { [ -n "$f_effort" ] && [ "$f_effort" != "$ef" ]; } && continue
    { [ -n "$f_type" ] && [ "$f_type" != "$tp" ]; } && continue
    { [ -n "$f_milestone" ] && [ "$f_milestone" != "$milv" ]; } && continue
    if [ "$depsat" = "1" ] && [ -n "$blockedBy" ]; then
      # a dep is satisfied iff its issue is CLOSED (terminal); look it up in the list
      local dep depstate skip=0 IFS=,
      for dep in $blockedBy; do
        depstate=$(_gh_liststate "$dep")
        [ "$depstate" = "CLOSED" ] || { skip=1; break; }
      done
      unset IFS
      [ "$skip" = "1" ] && continue
    fi
    # claimed_at for the summary (only when assigned)
    local clat=""; [ -n "$assignee" ] && clat=$(_gh_timeline "$num" | grep -v '^$' | tail -1 || true)
    [ "$first" = "1" ] || printf '\n'; first=0
    printf 'id=%s\ntitle=%s\npriority=%s\neffort=%s\ntype=%s\nmilestone=%s\nclaimed_by=%s\nclaimed_at=%s\ncreated=%s\n' \
      "$num" "$title" "$pr" "$ef" "$tp" "$milv" "$assignee" "$clat" "$created"
  done < "$TE_TMPD/ghlist"
  return 0
}
# state of issue $1 from the fetched list ("" if absent)
_gh_liststate() {
  local want=$1 num rest state
  while IFS="$US" read -r num title state rest; do
    [ "$num" = "$want" ] && { printf '%s\n' "$state"; return 0; }
  done < "$TE_TMPD/ghlist"
  return 0
}

# --- te deps check (github) --------------------------------------------------
cmd_deps_check_gh() {
  local id=$1 deps=$2 slate=$3
  if ! _gh_version_ok; then
    te_emit_fail "deps-check" "gh >= 2.94 is required (blockedBy JSON field); found $(gh --version 2>/dev/null | head -1)" \
      "upgrade gh, then re-run — a silent empty here would wrongly pass every ticket"
    return 1
  fi
  deps=$(printf '%s' "$deps" | tr ',' ' '); slate=$(printf '%s' "$slate" | tr ',' ' ')
  _gh_deps_raw > "$TE_TMPD/ghedges"
  # existence: each proposed dep must appear as an issue in the graph (either side
  # of an edge) unless slate-exempt. Build the known-id set from the edge list.
  { cut -f1 "$TE_TMPD/ghedges"; cut -f2 "$TE_TMPD/ghedges"; } | sort -u > "$TE_TMPD/ghnodes"
  local dep
  for dep in $deps; do
    [ -n "$dep" ] || continue
    case " $slate " in *" $dep "*) continue ;; esac
    grep -Fxq "$dep" "$TE_TMPD/ghnodes" || {
      te_emit_fail "deps-check" "depends_on references $dep, which does not exist" "fix the ID or drop the dependency"; return 1; }
  done
  { cat "$TE_TMPD/ghedges"; for dep in $deps; do [ -n "$dep" ] && printf '%s\t%s\n' "$id" "$dep"; done; } > "$TE_TMPD/ghalledges"
  local chain rc
  set +e; chain=$(awk -f "$TE_LIB/deps.awk" -v start="$id" "$TE_TMPD/ghalledges"); rc=$?; set -e
  if [ "$rc" -eq 2 ] && [ -n "$chain" ]; then
    te_emit_fail "deps-check" "depends_on cycle: $chain" "break the cycle by dropping one of the links"; return 1
  elif [ "$rc" -ne 0 ]; then
    te_internal "deps.awk failed (exit $rc) on the github dependency graph"
  fi
  echo "ok=true"
  return 0
}

# --- te milestone scan (github) ----------------------------------------------
cmd_milestone_scan_gh() {
  local want=$1 strat=$2
  if [ "$strat" = "native" ]; then
    local title state open closed
    while IFS="$TAB" read -r title state open closed; do
      [ -n "$title" ] || continue
      { [ -n "$want" ] && [ "$want" != "$title" ]; } && continue
      local drift=false
      # drift = every issue closed but milestone still open
      { [ "$state" = "open" ] && [ "${open:-0}" -eq 0 ] && [ "${closed:-0}" -ge 1 ]; } && drift=true
      printf 'version=%s\nstate=%s\nopen_issues=%s\nclosed_issues=%s\ndrift=%s\n\n' \
        "$title" "$state" "${open:-0}" "${closed:-0}" "$drift"
    done < <(_gh_milestones)
    return 0
  fi
  if [ "$strat" = "labels" ]; then
    _gh_list_raw all > "$TE_TMPD/ghlist"
    # roll up milestone: label distribution
    : > "$TE_TMPD/ghmls"
    local num title state sr created itype assignee mil blockedBy labels url v
    while IFS="$US" read -r num title state sr created itype assignee mil blockedBy labels url; do
      v=$(_label_suffix "$labels" "milestone:"); [ -n "$v" ] && printf '%s\n' "$v" >> "$TE_TMPD/ghmls"
    done < "$TE_TMPD/ghlist"
    local ver n
    for ver in $(sort -u "$TE_TMPD/ghmls"); do
      { [ -n "$want" ] && [ "$want" != "$ver" ]; } && continue
      n=$(grep -Fxc "$ver" "$TE_TMPD/ghmls" || true)
      printf 'version=%s\ncount=%s\n\n' "$ver" "$n"
    done
    return 0
  fi
  return 0   # none
}

# --- te projects resolve -----------------------------------------------------
cmd_projects_resolve() {
  local cfg=""
  while [ $# -gt 0 ]; do case "$1" in --dry-run) shift ;; *) cfg="$1"; shift ;; esac; done
  load_config "$cfg" || return 1
  local backend; backend=$(cfg_get backend.type)
  if [ "$backend" != "github" ] || [ "$(cfg_get projects.enabled || true)" != "true" ]; then
    echo "ok=true"; echo "note=projects resolve is a no-op (projects disabled or filesystem backend)"
    return 0
  fi
  local sf; sf=$(cfg_get projects.status_field || echo Status)
  local fields="$TE_TMPD/ghfields" found=""
  if ! _gh_fields_raw > "$fields" 2>/dev/null || [ ! -s "$fields" ]; then
    echo "ok=true"; echo "warning=could not resolve project fields (project deleted, or the token lacks the 'project' scope); set fields manually"
    return 0
  fi
  local fid fname ftype
  while IFS="$TAB" read -r fid fname ftype; do
    [ "$fname" = "$sf" ] && { printf 'status_field_id=%s\n' "$fid"; found=1; }
  done < "$fields"
  if [ -z "$found" ]; then
    echo "ok=true"; echo "warning=status field '$sf' not found on the board; project sync is a no-op this run"
    return 0
  fi
  echo "ok=true"
  return 0
}
