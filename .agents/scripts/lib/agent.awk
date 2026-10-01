# agent.awk — parse a generated agent file (or an agent-kind spec) into records,
# and write every marked region's body to <outdir>/<type>.<id> so the shell can
# compare contract regions byte-for-byte and hash the generated/user ones.
# Invoked as `awk -f agent.awk -v outdir=<dir> <file>`.
#
# Region markers (each on a line of its own):
#   <!-- contract:start id=<id> -->   …   <!-- contract:end id=<id> -->
#   <!-- generated:start id=<id> -->  …   <!-- generated:end id=<id> -->
#   <!-- user:start -->               …   <!-- user:end -->
# Kind marker:  <!-- agent-kind: <kind> -->
#
# Output records (TAB-separated):
#   FM <TAB> key <TAB> value         frontmatter scalar (single-line values)
#   KIND <TAB> kind                   the agent-kind marker
#   R <TAB> type <TAB> id             a region, in document order
#   E <TAB> message                   a structural error (first one wins; exit 1)
#
# BSD-awk clean.

function err(msg) { printf("E\t%s\n", msg); bad = 1; exit 1 }
function trim(s)  { gsub(/^[ \t]+/, "", s); gsub(/[ \t]+$/, "", s); return s }

BEGIN { fm = 0; open_t = ""; open_id = "" }

NR == 1 {
  if ($0 != "---") err("line 1 must be '---' — an agent file starts with its frontmatter (no comment or blank line before it)")
  fm = 1; next
}
fm == 1 {
  if ($0 == "---") { fm = 2; next }
  if (match($0, /^[A-Za-z_-]+:/)) {
    k = substr($0, 1, RLENGTH - 1); v = trim(substr($0, RLENGTH + 1))
    if (v ~ /^".*"$/ || v ~ /^'.*'$/) v = substr(v, 2, length(v) - 2)
    printf("FM\t%s\t%s\n", k, v)
  }
  next
}
fm != 2 { next }

/^<!-- agent-kind: [a-z0-9-]+ -->$/ {
  k = $0; sub(/^<!-- agent-kind: /, "", k); sub(/ -->$/, "", k)
  if (kind != "") err("more than one agent-kind marker")
  kind = k; printf("KIND\t%s\n", k); next
}

/^<!-- (contract|generated):(start|end) id=[a-z0-9-]+ -->$/ || /^<!-- user:(start|end) -->$/ {
  line = $0; sub(/^<!-- /, "", line); sub(/ -->$/, "", line)
  split(line, parts, " ")
  split(parts[1], te_, ":"); t = te_[1]; edge = te_[2]
  id = "user"
  if (t != "user") { id = parts[2]; sub(/^id=/, "", id) }
  if (edge == "start") {
    if (open_t != "") err("region " t ":" id " opens inside " open_t ":" open_id " (line " NR ") — regions never nest")
    if ((t SUBSEP id) in seen_r) err("region " t ":" id " appears more than once")
    seen_r[t, id] = 1
    open_t = t; open_id = id; outf = outdir "/" t "." id
    printf("") > outf
    printf("R\t%s\t%s\n", t, id)
  } else {
    if (open_t != t || open_id != id) err("region end " t ":" id " (line " NR ") does not close the open region" (open_t == "" ? "" : " " open_t ":" open_id))
    close(outf); open_t = ""; open_id = ""
  }
  next
}

/^<!-- (contract|generated|user)[:]/ { err("malformed region marker at line " NR ": " $0) }

open_t != "" { print > outf; next }

END {
  if (bad) exit 1
  if (fm == 1) { printf("E\tfrontmatter is never closed with '---'\n"); exit 1 }
  if (open_t != "") { printf("E\tregion %s:%s is never closed\n", open_t, open_id); exit 1 }
}
