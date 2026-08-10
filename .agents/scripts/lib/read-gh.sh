# read-gh.sh — the github read path (TE-004), conforming to TE-003's frozen
# field view. Reads render via `gh --template` (Go templates → flat key=value),
# never `gh --json` + awk. Sourced by te. bash 3.2 clean; all awk (deps.awk,
# board.awk) via -f. Mapping is offline-testable via TE_GH_FIXTURE (see below).
#
# REST ONLY. Every fetch below goes through `gh api` against the REST API, never
# `gh issue list/view --json` or `gh project *` — those are GraphQL wrappers, and
# they bill a SEPARATE, much scarcer budget. Measured against a live account:
#
#   gh project item-list (671-item board)  708 graphql points   (5000/hr bucket)
#   gh project item-list (36-item board)   104 graphql points
#   gh project field-list                  102 graphql points
#   gh issue list --json <11 fields>         3 graphql points / 100 issues
#   REST equivalent of ALL of the above      1 core request / 100 rows (5000/hr)
#
# A single `te read` against a 671-item board cost 708 of 5000 graphql points, so
# ~7 ticket operations exhausted the hour. The same read is now 8 REST requests.
# Projects v2 DOES have a REST API (users|orgs/{owner}/projectsV2/...); `gh
# project` simply does not use it. The one operation with no REST route is
# CREATING a project, which /ticket:init does once — see ../ticket-init/SKILL.md.
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
# REST payload shapes, confirmed against the live API (2026-08-10). The FROZEN
# FIELD VIEW is unchanged from the GraphQL era — the renames and the casing
# difference are absorbed here, inside the templates, so every mapping helper and
# every recorded fixture keeps its existing contract:
#   .html_url→url  .created_at→createdAt  .type.name→issueType
#   .state_reason→stateReason  and state/stateReason are re-spelled UPPERCASE
#   ({{if eq .state "closed"}}CLOSED…) to match what the mapping layer compares.
# `labels`/`assignees` are flat arrays; `milestone`/`type` are objects-or-null
# (guarded with {{if}}). REST /issues returns pull requests too, so every list
# template guards with {{if not .pull_request}}.
#
# EVERY NUMBER GOES THROUGH {{printf "%.0f" …}} — never bare {{.n}}. The template
# engine decodes JSON numbers to float64 and renders them with %v, which switches
# to scientific notation once the value is large enough: a board field id came
# back as `3.78309328e+08`, and issue numbers do the same past 1e6. The GraphQL
# ids this replaced were opaque strings (PVTSSF_…), so the trap is new to REST.
#
# `blockedBy` has NO bulk REST form. The payload does carry
# `issue_dependencies_summary`, so the list templates emit its COUNT and the
# fetch functions resolve real numbers with one
# /issues/{n}/dependencies/blocked_by call per issue that has any. Use
# total_blocked_by, NEVER blocked_by: blocked_by counts only OPEN blockers, and a
# dependency is satisfied precisely when its issue is CLOSED — gating on
# blocked_by would hide every already-satisfied edge from the graph and make
# --depends-satisfied wrongly pass.
#
# Flat key=value view of one issue, then the body after ---BODY---. blockedBy is
# interpolated by _gh_view as a literal (%s) so the body bytes are never touched.
TE_GH_VIEW_TMPL_FMT='number={{printf "%.0f" .number}}
title={{.title}}
state={{if eq .state "closed"}}CLOSED{{else}}OPEN{{end}}
stateReason={{if eq .state_reason "completed"}}COMPLETED{{else if eq .state_reason "not_planned"}}NOT_PLANNED{{else if eq .state_reason "duplicate"}}DUPLICATE{{end}}
createdAt={{.created_at}}
issueType={{if .type}}{{.type.name}}{{end}}
assignee={{range $i, $a := .assignees}}{{if $i}},{{end}}{{$a.login}}{{end}}
milestone={{if .milestone}}{{.milestone.title}}{{end}}
blockedBy=%s
labels={{range $i, $l := .labels}}{{if $i}},{{end}}{{$l.name}}{{end}}
url={{.html_url}}
---BODY---
{{.body}}'

# One line per issue for lists: fields separated by US (\x1f, a non-whitespace
# delimiter — a tab-IFS read collapses consecutive tabs and would eat empty
# middle fields like an absent stateReason/assignee). Body excluded. Column 9
# carries the total_blocked_by COUNT on the wire; _gh_list_raw rewrites it into
# the blockedBy CSV the frozen view specifies.
TE_GH_LIST_TMPL='{{range .}}{{if not .pull_request}}{{printf "%.0f" .number}}{{"\x1f"}}{{.title}}{{"\x1f"}}{{if eq .state "closed"}}CLOSED{{else}}OPEN{{end}}{{"\x1f"}}{{if eq .state_reason "completed"}}COMPLETED{{else if eq .state_reason "not_planned"}}NOT_PLANNED{{else if eq .state_reason "duplicate"}}DUPLICATE{{end}}{{"\x1f"}}{{.created_at}}{{"\x1f"}}{{if .type}}{{.type.name}}{{end}}{{"\x1f"}}{{range $i, $a := .assignees}}{{if $i}},{{end}}{{$a.login}}{{end}}{{"\x1f"}}{{if .milestone}}{{.milestone.title}}{{end}}{{"\x1f"}}{{if .issue_dependencies_summary}}{{printf "%.0f" .issue_dependencies_summary.total_blocked_by}}{{else}}0{{end}}{{"\x1f"}}{{range $i, $l := .labels}}{{if $i}},{{end}}{{$l.name}}{{end}}{{"\x1f"}}{{.html_url}}{{"\n"}}{{end}}{{end}}'

# number<TAB>total_blocked_by per issue; _gh_deps_raw expands the non-zero rows
# into the id<TAB>dep edge list deps.awk consumes.
TE_GH_DEPS_TMPL='{{range .}}{{if not .pull_request}}{{printf "%.0f" .number}}{{"\t"}}{{if .issue_dependencies_summary}}{{printf "%.0f" .issue_dependencies_summary.total_blocked_by}}{{else}}0{{end}}{{"\n"}}{{end}}{{end}}'

# number<TAB>created_at for every `assigned` event in the repo, newest-first on
# the wire. events.awk reduces it to one latest row per issue — the reduction
# takes the max rather than trusting that arrival order, since nothing in the API
# contract promises it.
TE_GH_EVENTS_TMPL='{{range .}}{{if eq .event "assigned"}}{{if .issue}}{{printf "%.0f" .issue.number}}{{"\t"}}{{.created_at}}{{"\n"}}{{end}}{{end}}{{end}}'

# One board item per line: url, then a NAME<RS>VALUE pair per requested field.
# board.awk reshapes it into the frozen url<US>priority<US>effort<US>risk view.
# A single-select value is an OBJECT in REST ({"name":{"raw":"P0"},...}), so the
# name is `.name.raw` — `{{.}}` would render the whole struct.
TE_GH_BOARD_TMPL='{{range .}}{{if .content.html_url}}{{.content.html_url}}{{range .fields}}{{"\t"}}{{.name}}{{"\x1e"}}{{with .value}}{{.name.raw}}{{end}}{{end}}{{"\n"}}{{end}}{{end}}'

# No row cap: every list fetch is `gh api --paginate`, which walks Link headers
# to exhaustion. (The GraphQL wrappers this replaced defaulted to 30 rows and
# needed an explicit --limit or they silently truncated the graph / board join.)
US=$(printf '\037') # unit separator: the field delimiter for multi-field rows

_gh_repo() { cfg_get backend.github.repo; }

_gh_owner() {  # owner half of owner/repo
  local r; r=$(_gh_repo); printf '%s\n' "${r%%/*}"
}

# REST projectsV2 route prefix for the configured board: users|orgs/<owner>/
# projectsV2/<number>. Returns 1 when no board is configured, so callers no-op.
#
# The owner kind is DETECTED (one memoised request), not read from config.
# projects.owner_type is unvalidated and drifts — a user-owned board configured
# `owner_type: org` is a real shape seen in the wild. The GraphQL wrappers this
# replaced resolved the owner themselves, so a wrong value was harmless; over
# REST it points at a route that 404s, and the board silently reads back empty
# (every priority/effort/risk falling through to the label fallback with no
# error). Detection costs one request per process and cannot drift, so config is
# consulted only when the probe itself fails — offline, or a token that cannot
# see the owner.
_gh_projects_base() {
  local num owner otype seg
  num=$(cfg_get projects.number || true); owner=$(cfg_get projects.owner || true)
  [ -n "$num" ] && [ -n "$owner" ] || return 1
  if [ -f "$TE_TMPD/ghownerseg" ]; then
    seg=$(cat "$TE_TMPD/ghownerseg")
  else
    case "$(gh api "users/$owner" -q .type 2>/dev/null)" in
      Organization) seg=orgs ;;
      User)         seg=users ;;
      *)  # probe failed — fall back to the recorded hint, then to users/
        otype=$(cfg_get projects.owner_type || true)
        case "$otype" in
          org|organization) seg=orgs ;;
          *)                seg=users ;;
        esac ;;
    esac
    printf '%s' "$seg" > "$TE_TMPD/ghownerseg"
  fi
  printf '%s/%s/projectsV2/%s\n' "$seg" "$owner" "$num"
}

# csv of the issue numbers blocking $1 ("" if none). One REST request; callers
# gate on total_blocked_by so this only fires for issues that actually have deps.
_gh_blocked_by() {
  gh api "repos/$(_gh_repo)/issues/$1/dependencies/blocked_by" --paginate \
    --template '{{range .}}{{printf "%.0f" .number}}{{","}}{{end}}' 2>/dev/null | sed 's/,$//'
}

# --- fetch functions (fixture-backed when TE_GH_FIXTURE is set) ---------------
_gh_view() {  # $1 issue number -> raw view (template output)
  if [ -n "${TE_GH_FIXTURE:-}" ]; then cat "$TE_GH_FIXTURE/issue-$1.view" 2>/dev/null; return; fi
  local deps tmpl
  # A single read is two requests either way, so resolve deps unconditionally
  # here rather than gating on the count (which would cost the same request).
  deps=$(_gh_blocked_by "$1")
  # Substitute into the TEMPLATE, not the rendered output: the body could
  # contain anything, including a line that looks like the blockedBy field.
  # Parameter expansion, not printf — the template must stay opaque to % and \.
  tmpl=${TE_GH_VIEW_TMPL_FMT/blockedBy=%s/blockedBy=$deps}
  gh api "repos/$(_gh_repo)/issues/$1" --template "$tmpl" 2>/dev/null
}
_gh_timeline() {  # $1 issue number -> one `assigned` event timestamp per line
  if [ -n "${TE_GH_FIXTURE:-}" ]; then cat "$TE_GH_FIXTURE/issue-$1.timeline" 2>/dev/null; return; fi
  gh api "repos/$(_gh_repo)/issues/$1/timeline" --paginate \
    --template '{{range .}}{{if eq .event "assigned"}}{{.created_at}}{{"\n"}}{{end}}{{end}}'
}

# number<TAB>latest-assigned-timestamp for EVERY issue in the repo, from one
# repo-wide sweep. Memoised for the process.
#
# `te list` derives claimed_at per row, and doing that with _gh_timeline cost one
# paginated request PER CLAIMED TICKET — measured at 32 requests for a single
# list on a 36-issue board. The repo-wide events feed carries the same `assigned`
# events with their issue number attached, so one sweep replaces all of them (7
# pages for that board). Cost scales with the repo's total event volume rather
# than with the number of claimed tickets, which is the better curve for a ticket
# board but NOT universally — `te read` keeps using _gh_timeline, where a single
# issue's timeline is one request and a whole-repo sweep would be absurd.
#
# The fixture seam sits on the RAW rows, before the reduction, so events.awk runs
# in offline tests too — a fixture of pre-reduced output would leave the
# latest-wins logic untested.
_gh_assigned_index() {
  local memo="$TE_TMPD/ghassigned" raw="$TE_TMPD/ghassignedraw"
  if [ -f "$memo" ]; then cat "$memo"; return 0; fi
  if [ -n "${TE_GH_FIXTURE:-}" ]; then
    cat "$TE_GH_FIXTURE/assigned-events.txt" > "$raw" 2>/dev/null || : > "$raw"
  else
    gh api "repos/$(_gh_repo)/issues/events?per_page=100" --paginate \
      --template "$TE_GH_EVENTS_TMPL" > "$raw" 2>/dev/null || : > "$raw"
  fi
  awk -f "$TE_LIB/events.awk" "$raw" > "$memo" 2>/dev/null || : > "$memo"
  cat "$memo"
}

# latest assigned timestamp for issue $1 from the index ("" if never assigned)
_gh_claimed_at() {
  local want=$1 n ts
  [ -f "$TE_TMPD/ghassignedidx" ] || return 0
  while IFS="$TAB" read -r n ts; do
    [ "$n" = "$want" ] && { printf '%s\n' "$ts"; return 0; }
  done < "$TE_TMPD/ghassignedidx"
  return 0
}
_gh_list_raw() {  # $1 state (open|all) -> one US line per issue
  if [ -n "${TE_GH_FIXTURE:-}" ]; then cat "$TE_GH_FIXTURE/issue-list-$1.txt" 2>/dev/null; return; fi
  local raw="$TE_TMPD/ghlistwire"
  gh api "repos/$(_gh_repo)/issues?state=$1&per_page=100" --paginate \
    --template "$TE_GH_LIST_TMPL" > "$raw" 2>/dev/null
  # Column 9 arrives as the total_blocked_by COUNT; expand it to the CSV the
  # frozen view specifies, paying a request only for issues that have deps.
  local num title st sr created itype assignee mil cnt labels url deps
  while IFS="$US" read -r num title st sr created itype assignee mil cnt labels url; do
    [ -n "$num" ] || continue
    deps=""
    [ "${cnt:-0}" != "0" ] && deps=$(_gh_blocked_by "$num")
    printf '%s'"$US"'%s'"$US"'%s'"$US"'%s'"$US"'%s'"$US"'%s'"$US"'%s'"$US"'%s'"$US"'%s'"$US"'%s'"$US"'%s\n' \
      "$num" "$title" "$st" "$sr" "$created" "$itype" "$assignee" "$mil" "$deps" "$labels" "$url"
  done < "$raw"
}
_gh_deps_raw() {  # id<TAB>dep edge list over all issues
  if [ -n "${TE_GH_FIXTURE:-}" ]; then cat "$TE_GH_FIXTURE/edges.txt" 2>/dev/null; return; fi
  local raw="$TE_TMPD/ghdepswire" num cnt dep deps
  gh api "repos/$(_gh_repo)/issues?state=all&per_page=100" --paginate \
    --template "$TE_GH_DEPS_TMPL" > "$raw" 2>/dev/null
  while IFS="$TAB" read -r num cnt; do
    [ -n "$num" ] || continue
    [ "${cnt:-0}" = "0" ] && continue
    deps=$(_gh_blocked_by "$num")
    # The summary said this issue has blockers; if the dependencies endpoint
    # then yields none, the graph is silently incomplete and every dependent
    # ticket would wrongly pass --depends-satisfied. Fail pointed instead.
    if [ -z "$deps" ]; then
      te_emit_fail "deps-check" \
        "issue #$num reports $cnt blocker(s) but repos/$(_gh_repo)/issues/$num/dependencies/blocked_by returned none" \
        "re-run; if it persists the token may lack read access to a blocking issue's repo — a silent empty here would wrongly pass every dependent ticket" >&2
      return 1
    fi
    local IFS=,
    for dep in $deps; do printf '%s\t%s\n' "$num" "$dep"; done
    unset IFS
  done < "$raw"
}
_gh_project_items() {  # url<US>priority<US>effort<US>risk from the board
  if [ -n "${TE_GH_FIXTURE:-}" ]; then cat "$TE_GH_FIXTURE/project-items.txt" 2>/dev/null; return; fi
  local base ids fid fname ftype pf ef rf
  base=$(_gh_projects_base) || return 0
  # The items endpoint returns only Title unless asked for fields BY NUMERIC ID,
  # so the field list has to be resolved first (one request, memoised).
  ids=""
  while IFS="$TAB" read -r fid fname ftype; do
    [ "$ftype" = "single_select" ] || continue
    ids="${ids:+$ids,}$fid"
  done < <(_gh_fields_raw)
  [ -n "$ids" ] || return 0
  pf=$(cfg_get projects.field_map.priority || echo Priority)
  ef=$(cfg_get projects.field_map.effort   || echo Effort)
  rf=$(cfg_get projects.field_map.risk     || echo Risk)
  gh api "$base/items?per_page=100&fields=$ids" --paginate \
    --template "$TE_GH_BOARD_TMPL" 2>/dev/null \
    | awk -f "$TE_LIB/board.awk" -v prio="$pf" -v eff="$ef" -v risk="$rf"
}
_gh_milestones() {  # title<TAB>state<TAB>open<TAB>closed per milestone
  if [ -n "${TE_GH_FIXTURE:-}" ]; then cat "$TE_GH_FIXTURE/milestones.txt" 2>/dev/null; return; fi
  gh api "repos/$(_gh_repo)/milestones?state=all" --paginate \
    --template '{{range .}}{{.title}}{{"\t"}}{{.state}}{{"\t"}}{{printf "%.0f" .open_issues}}{{"\t"}}{{printf "%.0f" .closed_issues}}{{"\n"}}{{end}}'
}
_gh_fields_raw() {  # id<TAB>name<TAB>data_type per board field
  if [ -n "${TE_GH_FIXTURE:-}" ]; then cat "$TE_GH_FIXTURE/project-fields.txt" 2>/dev/null; return; fi
  # Memoised: both _gh_project_items and cmd_projects_resolve want this, and a
  # board read would otherwise pay for the field list twice in one process.
  local memo="$TE_TMPD/ghfieldswire" base
  if [ ! -f "$memo" ]; then
    base=$(_gh_projects_base) || return 0
    gh api "$base/fields" --paginate \
      --template '{{range .}}{{printf "%.0f" .id}}{{"\t"}}{{.name}}{{"\t"}}{{.data_type}}{{"\n"}}{{end}}' \
      > "$memo" 2>/dev/null || : > "$memo"
  fi
  cat "$memo"
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
  # One repo-wide sweep up front, not one timeline request per claimed row.
  _gh_assigned_index > "$TE_TMPD/ghassignedidx"
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
    local clat=""; [ -n "$assignee" ] && clat=$(_gh_claimed_at "$num")
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
  deps=$(printf '%s' "$deps" | tr ',' ' '); slate=$(printf '%s' "$slate" | tr ',' ' ')
  # No gh version floor any more: the edge list is built from `gh api` REST
  # routes, which every gh that can authenticate can reach. _gh_deps_raw
  # hard-fails on its own if the graph comes back incomplete.
  _gh_deps_raw > "$TE_TMPD/ghedges" || return 1
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
