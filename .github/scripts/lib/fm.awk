# fm.awk — parse ticket-file frontmatter (already sliced out, no `---` fences)
# into key<TAB>value records. Unlike config.awk (a machine-config parser),
# frontmatter is HUMAN text: a value is opaque to end-of-line. No comment
# stripping, no quote/flow/anchor/tag interpretation — a title may legitimately
# contain `#`, start with `[` or `"`, etc., and must survive verbatim.
#
#   awk -f fm.awk <frontmatter-lines>
#
# Only the first `:` splits key from value; leading/trailing whitespace is
# trimmed off both. `null` normalization (for the nullable fields) is the
# caller's job, so a title of literally "null" is not clobbered here.
#
# Scope: single-line scalar frontmatter only (what the workflow generates).
# Block scalars, multi-line values, and duplicate keys are not modeled — the
# first occurrence of a key wins.

/^[ \t]*#/ { next }        # full-line comment
/^[ \t]*$/ { next }        # blank
{
  ci = index($0, ":")
  if (ci == 0) next        # not a `key: value` line (e.g. a stray continuation)
  key = substr($0, 1, ci - 1)
  sub(/^[ \t]+/, "", key); sub(/[ \t]+$/, "", key)
  val = substr($0, ci + 1)
  sub(/^[ \t]+/, "", val); sub(/[ \t]+$/, "", val)
  print key "\t" val
}
