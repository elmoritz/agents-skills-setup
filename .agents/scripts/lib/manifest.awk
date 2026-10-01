# manifest.awk — validate <bundle>/setup/manifest.yaml, the machine-owned record
# /ticket:init writes beside config.yaml: what the environment could do, what was
# detected in the repo, and where every decision came from. Input is config.awk's
# tagged records (the manifest uses the same YAML subset as the config).
#
#   V <TAB> key <TAB> value <TAB> line    scalar leaf / list item
#   T <TAB> key <TAB> list|map <TAB> line container marker
#
# On the first failing rule: print the message to stdout, exit 1. On success:
# print `ok=true` plus a one-line count per section, exit 0.
#
# BSD-awk clean (no gensub, no asort, no length(array)).

BEGIN {
  FS = "\t"
  CAP_STATUS = " verified unavailable "
  REQ_CAPS = "web_search subagents git"
  FACT_PROV = " detected asked "
  DEC_PROV = " asked detected default "
  CMD_ROLES = " test lint typecheck build "
  CMD_STATUS = " verified failing unavailable unverified skipped "
  RESEARCH_STATUS = " done thin "
}

$1 == "V" { key = $2; if (!(key in seen)) { ord[nord++] = key; seen[key] = 1 }
            val[key] = $3; next }
$1 == "T" { key = $2; if (!(key in seen)) { ord[nord++] = key; seen[key] = 1 }
            typ[key] = $3; next }

function has(k)     { return (k in val) || (k in typ) }
function inset(s,x) { return index(s, " " x " ") > 0 }
function fail(msg)  { print msg; exit 1 }
# length of a list of maps: count consecutive key.N.<field> prefixes
function maplistlen(k,   n, i, p, found) {
  n = 0
  while (1) {
    p = k "." n "."; found = 0
    for (i = 0; i < nord; i++) if (index(ord[i], p) == 1) { found = 1; break }
    if (!found) return n
    n++
  }
}

END {
  # ---- M1: version ----
  if (!has("version")) fail("manifest: version: 1 required.")
  if (val["version"] != "1")
    fail("manifest: unsupported version " val["version"] "; this engine expects 1.")

  # ---- M2: timestamps ----
  if (val["created_at"] == "") fail("manifest: created_at is required (ISO 8601).")
  if (val["updated_at"] == "") fail("manifest: updated_at is required (ISO 8601).")

  # ---- M3: environment probe ----
  if (typ["environment"] != "map") fail("manifest: environment must be a map of capability: verified|unavailable.")
  nreq = split(REQ_CAPS, req, " ")
  for (i = 1; i <= nreq; i++)
    if (!(("environment." req[i]) in val))
      fail("manifest: environment." req[i] " is required — probe it; nothing is recorded from memory.")
  for (i = 0; i < nord; i++) {
    k = ord[i]
    if (index(k, "environment.") != 1 || !(k in val)) continue
    if (!inset(CAP_STATUS, val[k]))
      fail("manifest: " k " must be 'verified' or 'unavailable', got '" val[k] "' — there is no third state.")
    ncap++
  }

  # ---- M4: facts ----
  nfacts = 0
  if (has("facts")) {
    if (typ["facts"] != "list") fail("manifest: facts must be a list.")
    nfacts = maplistlen("facts")
    for (i = 0; i < nfacts; i++) {
      p = "facts." i "."
      if (val[p "key"] == "")    fail("manifest: facts[" i "]: missing 'key'.")
      if (!((p "value") in val)) fail("manifest: facts[" i "] (" val[p "key"] "): missing 'value'.")
      if (val[p "source"] == "") fail("manifest: facts[" i "] (" val[p "key"] "): missing 'source' — every fact names the file or command it came from.")
      if (!inset(FACT_PROV, val[p "provenance"]))
        fail("manifest: facts[" i "] (" val[p "key"] "): provenance must be 'detected' or 'asked', got '" val[p "provenance"] "'.")
    }
  }

  # ---- M5: decisions ----
  ndec = 0
  if (has("decisions")) {
    if (typ["decisions"] != "list") fail("manifest: decisions must be a list.")
    ndec = maplistlen("decisions")
    for (i = 0; i < ndec; i++) {
      p = "decisions." i "."
      dk = val[p "key"]
      if (dk == "") fail("manifest: decisions[" i "]: missing 'key'.")
      if (dk in dec_seen) fail("manifest: decisions: duplicate key '" dk "'.")
      dec_seen[dk] = 1
      if (!((p "value") in val) && typ[p "value"] == "")
        fail("manifest: decisions[" i "] (" dk "): missing 'value'.")
      if (!inset(DEC_PROV, val[p "provenance"]))
        fail("manifest: decisions[" i "] (" dk "): provenance must be asked, detected, or default, got '" val[p "provenance"] "'.")
    }
  }

  # ---- M6: commands ----
  ncmd = 0
  if (has("commands")) {
    if (typ["commands"] != "list") fail("manifest: commands must be a list.")
    ncmd = maplistlen("commands")
    for (i = 0; i < ncmd; i++) {
      p = "commands." i "."
      cr = val[p "role"]; cs = val[p "status"]
      if (!inset(CMD_ROLES, cr))
        fail("manifest: commands[" i "]: role must be test, lint, typecheck, or build, got '" cr "'.")
      if (val[p "command"] == "") fail("manifest: commands[" i "] (" cr "): missing 'command'.")
      if (val[p "source"] == "")  fail("manifest: commands[" i "] (" cr "): missing 'source' — where the command was found.")
      if (!inset(CMD_STATUS, cs))
        fail("manifest: commands[" i "] (" cr "): status must be verified, failing, unavailable, unverified, or skipped, got '" cs "'.")
      if ((cs == "verified" || cs == "failing") && (val[p "baseline"] == "" || val[p "checked_at"] == ""))
        fail("manifest: commands[" i "] (" cr "): a command that ran (" cs ") records its baseline and checked_at.")
    }
  }

  # ---- M7: research ----
  nsub = 0
  if (has("research")) {
    if (val["environment.web_search"] != "verified")
      fail("manifest: research is recorded but environment.web_search is not verified — research never comes from a session that could not search.")
    if (val["research.researched_at"] == "") fail("manifest: research.researched_at is required (ISO 8601).")
    if (has("research.subjects")) {
      if (typ["research.subjects"] != "list") fail("manifest: research.subjects must be a list.")
      nsub = maplistlen("research.subjects")
    }
    for (i = 0; i < nsub; i++) {
      p = "research.subjects." i "."
      sid = val[p "id"]
      if (sid == "") fail("manifest: research.subjects[" i "]: missing 'id'.")
      if (sid in sub_seen) fail("manifest: research.subjects: duplicate id '" sid "'.")
      sub_seen[sid] = 1
      if (val[p "subject"] == "") fail("manifest: research.subjects[" i "] (" sid "): missing 'subject'.")
      if (!inset(RESEARCH_STATUS, val[p "status"]))
        fail("manifest: research.subjects[" i "] (" sid "): status must be done or thin, got '" val[p "status"] "'.")
      if (val[p "notes"] == "") fail("manifest: research.subjects[" i "] (" sid "): missing 'notes' — the notes file the agents are built from.")
      if (!((p "queries.0") in val)) fail("manifest: research.subjects[" i "] (" sid "): record the queries that were run.")
      if (val[p "status"] == "done" && (val[p "sources"] + 0) < 1)
        fail("manifest: research.subjects[" i "] (" sid "): a done subject cites at least one source.")
    }
  }

  print "ok=true"
  print "environment=" ncap
  print "facts=" nfacts
  print "decisions=" ndec
  print "commands=" ncmd
  print "research_subjects=" nsub
}
