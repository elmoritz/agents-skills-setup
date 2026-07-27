# deps.awk — depth-first cycle walk over a dependency graph. Consumes a flat
# `id<TAB>dep` edge list (one edge per line) and reports the first cycle as the
# full chain (e.g. `TE-007 → TE-012 → TE-007`).
#
#   awk -f deps.awk -v start=TE-007 edges.txt   # walk from one node
#   awk -f deps.awk edges.txt                    # walk from every node
#
# The ledger front end (helpers.sh) and TE-004's gh-rendered edge list both feed
# this same walk — the graph source is the only backend-specific part, so the
# DFS exists exactly once. Existence checks live in the caller; this is a pure
# graph walk. Exit 0 = acyclic, 2 = cycle found (chain on stdout), 3 = usage.
#
# BSD-awk clean: recursion with extra-parameter locals (arrays localized per
# frame), split(), no gensub/asort.

BEGIN { FS = "\t" }

{
  # accumulate edges; record every node so the walk-all mode can enumerate them
  if ($1 != "") {
    adj[$1] = adj[$1] " " $2
    if (!($1 in seen)) { nodeord[nn++] = $1; seen[$1] = 1 }
    if ($2 != "" && !($2 in seen)) { nodeord[nn++] = $2; seen[$2] = 1 }
  }
}

# Walk node; onpath/path/np/done are shared (walk state); i/m/d/arr are locals.
function walk(node,   i, m, d, arr) {
  if (node in done) return
  onpath[node] = 1
  path[np++] = node
  m = split(adj[node], arr, " ")
  for (i = 1; i <= m; i++) {
    d = arr[i]
    if (d == "") continue
    if (d in onpath) { report_cycle(d); exit 2 }
    walk(d)
  }
  np--
  delete onpath[node]
  done[node] = 1
}

function report_cycle(d,   j, s, on) {
  s = ""; on = 0
  for (j = 0; j < np; j++) {
    if (path[j] == d) on = 1
    if (on) s = s (s == "" ? "" : " → ") path[j]
  }
  print s " → " d
}

END {
  if (start != "") { walk(start) }
  else { for (k = 0; k < nn; k++) walk(nodeord[k]) }
}
