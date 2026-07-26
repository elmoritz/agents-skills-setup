# msg.awk — render a commit/comment message from a `commits.<event>` template
# (§ Message formatting). One left-to-right pass over the template: each
# recognized {placeholder} is replaced with its value and the emitted text is
# never re-scanned, so a value that itself contains "{id}" is not re-substituted.
#
#   TE_MSG_TMPL="<template>" TE_MSG_id=… TE_MSG_title=… awk -f msg.awk
#
# Both the template and the values arrive via ENVIRON (TE_MSG_TMPL and
# TE_MSG_<name>), not -v, so quotes, backticks, $, newlines, and backslashes all
# survive intact (-v would interpret backslash escapes). Unknown placeholders
# are emitted verbatim.

BEGIN {
  tmpl = ENVIRON["TE_MSG_TMPL"]
  n = length(tmpl)
  out = ""
  i = 1
  while (i <= n) {
    c = substr(tmpl, i, 1)
    if (c == "{") {
      j = index(substr(tmpl, i + 1), "}")
      if (j == 0) { out = out substr(tmpl, i); break }   # unterminated: literal
      name = substr(tmpl, i + 1, j - 1)
      if (name == "id" || name == "title" || name == "target_id" ||
          name == "status" || name == "version" || name == "reason") {
        out = out ENVIRON["TE_MSG_" name]                 # unset -> empty string
      } else {
        out = out "{" name "}"                            # unknown: emit literally
      }
      i = i + j + 1
    } else {
      out = out c
      i = i + 1
    }
  }
  printf "%s\n", out
}
