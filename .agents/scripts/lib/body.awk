# body.awk — validate_type_body(): check that a ticket body carries each
# required section as a heading, and that the known-type non-empty sections have
# content. A section is matched by its config key: the heading text is
# normalized (lowercased, non-alphanumeric runs -> "_", trimmed) and compared to
# the key. /ticket:init's generated TICKET_TEMPLATE.md titles each section by its
# key, so a template-conformant body matches; a project that retitles sections
# must keep the heading's normalized form equal to the key.
#
#   awk -f body.awk -v req="why,acceptance_criteria" -v nonempty="acceptance_criteria" <file>
#
# Level-2-or-deeper ATX headings (`## `, `### `, …) are considered. Exit 0 =
# all required sections present (and non-empty where required); 1 = missing.

function norm(h,   s) {
  sub(/^#+[ \t]*/, "", h)
  s = tolower(h)
  gsub(/[^a-z0-9]+/, "_", s)
  gsub(/^_+/, "", s); gsub(/_+$/, "", s)
  return s
}

BEGIN {
  nr = split(req, R, ",")
  ne = split(nonempty, NE, ",")
  for (i = 1; i <= ne; i++) if (NE[i] != "") neset[NE[i]] = 1
  curkey = ""
}

/^##+[ \t]/ { curkey = norm($0); present[curkey] = 1; next }
{ if (curkey != "" && $0 ~ /[^ \t]/) hascontent[curkey] = 1 }

END {
  miss = ""
  for (i = 1; i <= nr; i++) {
    k = R[i]
    if (k == "") continue
    if (!(k in present)) { miss = miss (miss == "" ? "" : ",") k; continue }
    if ((k in neset) && !(k in hascontent)) miss = miss (miss == "" ? "" : ",") k
  }
  if (miss == "") { print "ok=true"; exit 0 }
  print "ok=false"; print "missing=" miss; exit 1
}
