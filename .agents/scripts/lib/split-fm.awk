# split-fm.awk — locate the end of a ticket file's YAML frontmatter. Prints the
# line number of the closing `---` fence, or nothing if the file has no
# frontmatter (first line is not `---`, or no closing fence is found).
#
#   awk -f split-fm.awk <ticket.md>
#
# read-fs.sh uses this line number to slice frontmatter (sed) and body
# (tail -n +N) with the shell, NOT awk — so the body round-trips byte-for-byte,
# including trailing whitespace and a missing final newline, which awk's
# line-by-line print would not preserve.

# Assumes a ticket has frontmatter: a frontmatter-less file whose first body
# line is literally `---` would be misread as opening a fence. Workflow-written
# tickets always carry frontmatter, so this holds.
NR == 1 && $0 == "---" { infm = 1; next }
infm && $0 == "---"    { print NR; exit }
