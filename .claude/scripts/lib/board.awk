# board.awk — reshape projectsV2 REST item rows into the frozen board view.
#
# In:  url <TAB> NAME<RS>VALUE <TAB> NAME<RS>VALUE ...   (TE_GH_BOARD_TMPL)
# Out: url <US> priority <US> effort <US> risk
#
# The REST items endpoint returns the requested fields as a LIST, in no
# guaranteed order and omitting nothing, so the three columns are selected by
# NAME (from projects.field_map, passed in as -v) rather than by position. A
# field the board does not carry, or carries unset, yields an empty column —
# which is exactly what the caller's label fallback keys off.
#
# Splitting on index/substr rather than a regex keeps the RS byte (\x1e) out of
# a bracket expression, which BSD and gawk disagree about.

BEGIN {
  FS = "\t"
  US = sprintf("%c", 31)
  RS_ = sprintf("%c", 30)
}

{
  p = ""; e = ""; r = ""
  for (i = 2; i <= NF; i++) {
    j = index($i, RS_)
    if (j == 0) continue
    k = substr($i, 1, j - 1)
    v = substr($i, j + 1)
    if (k == prio) p = v
    else if (k == eff) e = v
    else if (k == risk) r = v
  }
  printf "%s%s%s%s%s%s%s\n", $1, US, p, US, e, US, r
}
