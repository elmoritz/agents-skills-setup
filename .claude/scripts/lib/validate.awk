# validate.awk — the 18 § Config rules of ticket-engine/SKILL.md, applied in
# order against config.awk's tagged records plus `A <TAB> name` agent-existence
# records (emitted by common.sh, which can stat the filesystem where awk cannot).
#
#   V <TAB> key <TAB> value <TAB> line    scalar leaf / list item
#   T <TAB> key <TAB> list|map <TAB> line container marker
#   A <TAB> name                          an agent file that exists in the bundle
#
# On the first failing rule: print the exact spec message to stdout, exit 1.
# On success: print the resolved config (leaves in document order + injected
# defaults) and the derived roles->stage map to stdout, exit 0.
#
# BSD-awk clean. Iteration that feeds a message uses the document-ordered ord[]
# so output and error selection are deterministic (for..in is unordered).

BEGIN {
  FS = "\t"
  VALID_ROLES = " inbox pickable in_progress review terminal "
  CANON_EFFORT = " S M L XL "
  MS_STRAT = " auto trackers native labels none "
}

$1 == "V" { key = $2; if (!(key in seen)) { ord[nord++] = key; seen[key] = 1 }
            val[key] = $3; vln[key] = $4; next }
$1 == "T" { key = $2; if (!(key in seen)) { ord[nord++] = key; seen[key] = 1 }
            typ[key] = $3; next }
$1 == "A" { agent[$2] = 1; next }

function has(k)     { return (k in val) || (k in typ) }
function inset(s,x) { return index(s, " " x " ") > 0 }

# number of consecutive indexed children key.0, key.1, ... (list length)
function listlen(k,   n) { n = 0; while ((k "." n) in val) n++; return n }
# does any record key live under k (i.e. k.<something>)? distinguishes an empty
# container from a populated one, for both maps (named children) and lists.
function has_children(k,   i, p) {
  p = k "."
  for (i = 0; i < nord; i++) if (index(ord[i], p) == 1) return 1
  return 0
}

function fail(msg) { print msg; exit 1 }

END {
  # ---- Rule 1: version ----
  if (!has("version")) fail("version: 1 required.")
  if (val["version"] != "1")
    fail("Unsupported config version " val["version"] "; this engine expects 1.")

  # ---- Rule 2: backend.type ----
  bt = val["backend.type"]
  if (bt != "filesystem" && bt != "github")
    fail("backend.type must be 'filesystem' or 'github', got '" bt "'.")

  # ---- Rule 3: matching backend block ----
  if (typ["backend." bt] != "map")
    fail("backend." bt ": block is required on backend.type: " bt ".")

  # ---- Rule 4: stages list + required fields ----
  if (typ["lifecycle.stages"] != "list") fail("lifecycle.stages must be a non-empty list.")
  nst = 0; while (("lifecycle.stages." nst) in typ) nst++
  if (nst == 0) fail("lifecycle.stages must be a non-empty list.")
  for (i = 0; i < nst; i++) {
    b = "lifecycle.stages." i
    if (!has(b ".key"))   fail("lifecycle.stages[" i "]: missing 'key'.")
    if (!has(b ".label")) fail("lifecycle.stages[" i "]: missing 'label'.")
    if (typ[b ".roles"] != "list") fail("lifecycle.stages[" i "]: 'roles' must be a list.")
    if (typ[b "." bt] != "map")
      fail("lifecycle.stages[" i "]: missing '" bt "' sub-block for backend.type: " bt ".")
  }

  # ---- Rule 5: unique stage keys ----
  for (i = 0; i < nst; i++) {
    sk = val["lifecycle.stages." i ".key"]
    if (sk in stagekey_seen) fail("lifecycle.stages: duplicate stage key '" sk "'.")
    stagekey_seen[sk] = 1
  }

  # ---- Role scan (feeds rules 6 and 7) ----
  for (i = 0; i < nst; i++) {
    b = "lifecycle.stages." i ".roles"
    nr = listlen(b)
    for (j = 0; j < nr; j++) {
      r = val[b "." j]
      rolecount[r]++
      if (!inset(VALID_ROLES, r) && badrole == "") { badrole = r; badidx = i }
      if (inset(VALID_ROLES, r)) rolestage[r] = val["lifecycle.stages." i ".key"]
    }
  }

  # ---- Rule 6: exactly one required role each; optional at most one ----
  split("pickable in_progress terminal", req, " ")
  for (i = 1; i <= 3; i++)
    if (rolecount[req[i]] != 1)
      fail("exactly one stage must carry the '" req[i] "' role (found " (rolecount[req[i]] + 0) ").")
  split("inbox review", opt, " ")
  for (i = 1; i <= 2; i++)
    if (rolecount[opt[i]] > 1)
      fail("at most one stage may carry the '" opt[i] "' role (found " rolecount[opt[i]] ").")

  # ---- Rule 7: unknown role names ----
  if (badrole != "")
    fail("lifecycle.stages[" badidx "].roles: unknown role '" badrole \
         "'. Valid roles: inbox, pickable, in_progress, review, terminal.")

  # ---- Rule 8: types map, each entry has required_body_sections (list) ----
  if (typ["types"] != "map") fail("types must be a map with at least one entry.")
  ntypes = 0
  for (i = 0; i < nord; i++) {
    k = ord[i]
    if (k ~ /^types\.[^.]+$/) {
      tname = substr(k, 7)
      typenames[tname] = 1; ntypes++
      if (typ["types." tname ".required_body_sections"] != "list")
        fail("types." tname ": required_body_sections is required (a list, may be empty).")
    }
  }
  if (ntypes == 0) fail("types must be a map with at least one entry.")

  # ---- Rule 9: effort subsets ----
  if (typ["effort.allowed"] != "list") fail("effort.allowed must be a list.")
  na = listlen("effort.allowed")
  for (i = 0; i < na; i++) {
    e = val["effort.allowed." i]
    if (!inset(CANON_EFFORT, e)) fail("effort.allowed: '" e "' is not one of S, M, L, XL.")
    allowed_set[e] = 1
  }
  if (typ["effort.pickable_allowed"] != "list") fail("effort.pickable_allowed must be a list.")
  np = listlen("effort.pickable_allowed")
  for (i = 0; i < np; i++) {
    e = val["effort.pickable_allowed." i]
    if (!inset(CANON_EFFORT, e)) fail("effort.pickable_allowed: '" e "' is not one of S, M, L, XL.")
    if (!(e in allowed_set)) fail("effort.pickable_allowed: '" e "' is not in effort.allowed.")
  }

  # ---- Rule 10: milestone strategy ----
  ms = val["milestones.strategy"]
  if (!inset(MS_STRAT, ms))
    fail("milestones.strategy must be one of auto, trackers, native, labels, none, got '" ms "'.")

  # ---- Rule 11: trackers is filesystem-only ----
  if (bt == "github" && ms == "trackers") fail("milestones.strategy: trackers is filesystem-only.")
  # ---- Rule 12: native is github-only ----
  if (bt == "filesystem" && ms == "native") fail("milestones.strategy: native is GitHub-only.")

  # ---- Rule 13: projects linkage ----
  enabled = (val["projects.enabled"] == "true")
  if (bt == "filesystem") {
    if (enabled)
      fail("projects linkage is github-only; set projects.enabled: false on the filesystem backend.")
  } else if (bt == "github" && enabled) {
    if (!has("projects.number") || val["projects.number"] !~ /^[0-9]+$/)
      fail("projects.number (integer) is required when projects.enabled: true.")
    if (!has("projects.owner") || val["projects.owner"] == "")
      fail("projects.owner (string) is required when projects.enabled: true.")
    for (i = 0; i < nord; i++) {
      k = ord[i]
      if (k ~ /^projects\.status_map\.[^.]+$/) {
        seg = substr(k, 21)
        # keys must be a subset of the *declared* stage roles, not just the
        # vocabulary — a status_map entry for a role no stage carries is a bug.
        if (!(seg in rolestage)) fail("projects.status_map: unknown role '" seg "'.")
        if (val[k] == "") fail("projects.status_map: '" seg "' must map to a non-empty option name.")
      }
      if (k ~ /^projects\.field_map\.[^.]+$/) {
        seg = substr(k, 20)
        if (seg != "priority" && seg != "effort" && seg != "risk")
          fail("projects.field_map: unknown field '" seg "'. Valid fields: priority, effort, risk.")
        if (val[k] == "") fail("projects.field_map: '" seg "' must map to a non-empty board field name.")
      }
    }
  }

  # ---- Rule 14: claim.stale_after ----
  if (has("claim.stale_after") && val["claim.stale_after"] !~ /^[1-9][0-9]*[hd]$/)
    fail("claim.stale_after: expected a duration like 24h or 3d, got '" val["claim.stale_after"] "'.")

  # ---- Rule 15: backend.github.type_map ----
  if (bt == "filesystem") {
    if (has("backend.github.type_map")) fail("backend.github.type_map is github-only.")
  } else {
    if (typ["backend.github.type_map"] == "map") {
      for (i = 0; i < nord; i++) {
        k = ord[i]
        if (k ~ /^backend\.github\.type_map\.[^.]+$/) {
          seg = substr(k, 25)
          if (!(seg in typenames)) fail("backend.github.type_map: '" seg "' is not a declared type.")
          if (val[k] == "") fail("backend.github.type_map: '" seg "' must map to a non-empty issue-type name.")
        }
      }
    }
  }

  # ---- Rule 16: research.agents ----
  if (has("research.agents")) {
    if (typ["research.agents"] != "list") fail("research.agents must be a list.")
    nra = 0; while (("research.agents." nra) in typ) nra++
    # entries are {name, consult} maps; a flow list of bare names is malformed
    # and must not slip through with zero checks
    if (listlen("research.agents") > 0)
      fail("research.agents entries must be name/consult maps, not bare names.")
    for (i = 0; i < nra; i++) {
      nm = val["research.agents." i ".name"]
      if (nm == "") fail("research.agents[" i "]: missing 'name'.")
      if (nm in ra_seen) fail("research.agents: duplicate name '" nm "'.")
      ra_seen[nm] = 1
      if (!(nm in agent))
        fail("research.agents: '" nm "' does not resolve to an agent file in the agents directory")
      if (val["research.agents." i ".consult"] == "")
        fail("research.agents: '" nm "' consult hint must be a non-empty one-line string.")
    }
  }

  # ---- Rule 17: review.agents ----
  if (has("review.agents")) {
    if (typ["review.agents"] != "list") fail("review.agents must be a list.")
    nrv = listlen("review.agents")
    if (nrv == 0) fail("review.agents must be a non-empty list.")
    for (i = 0; i < nrv; i++) {
      nm = val["review.agents." i]
      if (!(nm in agent))
        fail("review.agents: '" nm "' does not resolve to an agent file in the agents directory")
    }
  }

  # ---- Rule 18: verification.max_loop_rounds ----
  if (has("verification.max_loop_rounds") && val["verification.max_loop_rounds"] !~ /^[1-9][0-9]*$/)
    fail("verification.max_loop_rounds: expected a positive integer, got '" \
         val["verification.max_loop_rounds"] "'.")

  # ---- Success: resolved config ----
  # Leaves in document order, plus an explicit marker for a *declared but empty*
  # container so a leaf-less entry (e.g. required_body_sections: []) survives to
  # the consumer rather than vanishing (empty is not absent).
  for (i = 0; i < nord; i++) {
    k = ord[i]
    if (k in val) { print k "=" val[k]; continue }
    if ((k in typ) && !has_children(k)) print k "=" (typ[k] == "list" ? "[]" : "{}")
  }

  # injected defaults (only when absent)
  print "# --- resolved defaults ---"
  if (!has("claim.stale_after"))            print "claim.stale_after=24h"
  if (!has("verification.max_loop_rounds")) print "verification.max_loop_rounds=3"
  if (bt == "github" && enabled) {
    if (!has("projects.status_field"))   print "projects.status_field=Status"
    if (!has("projects.field_map.priority")) print "projects.field_map.priority=Priority"
    if (!has("projects.field_map.effort"))   print "projects.field_map.effort=Effort"
    if (!has("projects.field_map.risk"))     print "projects.field_map.risk=Risk"
  }

  # derived roles -> stage map
  print "# --- roles -> stage ---"
  split("inbox pickable in_progress review terminal", allroles, " ")
  for (i = 1; i <= 5; i++)
    if (allroles[i] in rolestage) print "roles." allroles[i] "=" rolestage[allroles[i]]
}
