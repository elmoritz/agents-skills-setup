# events.awk — reduce the repo-wide `assigned` event feed to one row per issue.
#
# In:  number <TAB> created_at      (many rows per issue, any order)
# Out: number <TAB> latest created_at   (one row per issue)
#
# The claim clock is the created_at of an issue's MOST RECENT `assigned` event
# (ticket-engine § Claim identity & staleness), so this keeps the max, not the
# first or last seen. The feed arrives newest-first today, but nothing in the
# API contract guarantees that and a re-assignment sweep spanning a page
# boundary would be exactly the case that breaks a first-wins shortcut.
#
# ISO-8601 UTC timestamps (…Z, fixed width) compare correctly as strings, which
# is why this needs no date parsing.

BEGIN { FS = "\t" }

$1 != "" && $2 != "" {
  if (!($1 in latest) || $2 > latest[$1]) latest[$1] = $2
}

END {
  for (n in latest) printf "%s\t%s\n", n, latest[n]
}
