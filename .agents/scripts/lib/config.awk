# config.awk — flatten the YAML subset /ticket:init generates into tagged,
# document-ordered records. Invoked as `awk -f config.awk -v path=<file> <file>`.
#
# Output records (TAB-separated), in document order:
#   V <TAB> dotted.key <TAB> value <TAB> line     a scalar leaf (incl. list items key.N)
#   T <TAB> dotted.key <TAB> list|map <TAB> line  a container marker (emitted once)
#
# An empty flow list `x: []` emits only `T x list <line>` (no V rows), so it is
# distinguishable from an absent key (no records at all). Same for empty maps.
#
# The subset: 2-space-indented block maps and block lists, `key: value` scalars
# (bare / "double" / 'single' quoted), inline flow lists `[a, b]`, `#` comments.
# Anything outside it — tabs, anchors/aliases (& *), tags (!), block scalars
# (| >), flow maps ({ }), nested flow ([[ , [{ ) — is a hard parse error, never a
# silent misparse: a hand-edited config that drifts out of subset must die
# pointed, per TE-001.
#
# BSD-awk clean: no gensub, no asort, no length(array); associative arrays,
# split(), match(), substr(), index(), gsub() only.

function parse_err(reason, ln) {
  printf("Could not parse %s: %s at line %d\n", path, reason, ln) > "/dev/stderr"
  exit 1
}

function emit_T(key, kind, ln) { printf("T\t%s\t%s\t%d\n", key, kind, ln) }
function emit_V(key, val, ln)  { printf("V\t%s\t%s\t%d\n", key, val, ln) }

# Pop frames whose indent is >= ind (siblings + deeper cld).
function pop_to(ind) {
  while (ns > 1 && f_ind[ns-1] >= ind) ns--
}

# Set the kind of frame fi, emitting its T marker once. Conflicting kinds
# (a map key where a list item was seen, or vice versa) is a parse error.
function set_kind(fi, k, ln,   key) {
  if (f_kind[fi] == "unknown") {
    f_kind[fi] = k
    key = f_pre[fi]
    if (key != "" && k != "scalar") emit_T(key, k, ln)
  } else if (f_kind[fi] != k) {
    parse_err("inconsistent nesting (expected " f_kind[fi] ", got " k ")", ln)
  }
}

# Strip surrounding whitespace.
function trim(s) { gsub(/^[ \t]+/, "", s); gsub(/[ \t]+$/, "", s); return s }

# Split a flow-list interior on commas, honoring quotes; emit each item.
function emit_flow(key, inner, ln,   i, c, cur, q, n) {
  emit_T(key, "list", ln)
  inner = trim(inner)
  if (inner == "") return            # empty list []
  n = 0; cur = ""; q = ""
  for (i = 1; i <= length(inner); i++) {
    c = substr(inner, i, 1)
    if (q != "") {
      if (c == q) q = ""; else cur = cur c
    } else if (c == "\"" || c == "'") {
      q = c
    } else if (c == ",") {
      emit_V(key "." n, trim(cur), ln); n++; cur = ""
    } else {
      cur = cur c
    }
  }
  if (q != "") parse_err("unterminated quote in flow list", ln)
  emit_V(key "." n, trim(cur), ln)
}

# Parse a scalar/flow value and emit it under fullkey.
function parse_value(fullkey, raw, ln,   c, cl, inner, v, rest) {
  raw = trim(raw)
  c = substr(raw, 1, 1)
  if (c == "|" || c == ">") parse_err("block scalars (| >) are out of subset", ln)
  if (c == "&" || c == "*") parse_err("anchors/aliases (& *) are out of subset", ln)
  if (c == "!")             parse_err("tags (!) are out of subset", ln)
  if (c == "{")             parse_err("flow mappings ({}) are out of subset", ln)
  if (c == "[") {
    cl = index(raw, "]")
    if (cl == 0) parse_err("unterminated flow list", ln)
    inner = substr(raw, 2, cl - 2)
    if (index(inner, "[") > 0 || index(inner, "{") > 0)
      parse_err("nested flow collections are out of subset", ln)
    rest = trim(substr(raw, cl + 1))
    if (rest != "" && substr(rest, 1, 1) != "#")
      parse_err("unexpected content after flow list", ln)
    emit_flow(fullkey, inner, ln)
    return
  }
  if (c == "\"" || c == "'") {
    cl = index(substr(raw, 2), c)
    if (cl == 0) parse_err("unterminated quote", ln)
    v = substr(raw, 2, cl - 1)
    rest = trim(substr(raw, cl + 2))
    if (rest != "" && substr(rest, 1, 1) != "#")
      parse_err("unexpected content after quoted value", ln)
    emit_V(fullkey, v, ln)
    return
  }
  # bare scalar: strip a trailing " # comment"
  v = raw
  if (match(v, / +#/)) v = substr(v, 1, RSTART - 1)
  emit_V(fullkey, trim(v), ln)
}

function handle_kv(content, indent, ln,   ci, key, raw, parent, fullkey) {
  pop_to(indent)
  parent = ns - 1
  ci = index(content, ":")
  if (ci == 0) {
    # no colon: only legal as a bare scalar list item (parent has a real prefix)
    if (f_pre[parent] == "") parse_err("expected 'key: value'", ln)
    set_kind(parent, "scalar", ln)
    parse_value(f_pre[parent], content, ln)
    return
  }
  key = trim(substr(content, 1, ci - 1))
  raw = substr(content, ci + 1)
  if (key ~ /[^A-Za-z0-9_.\-]/) parse_err("unexpected key '" key "'", ln)
  if (key == "") parse_err("empty key", ln)
  set_kind(parent, "map", ln)
  fullkey = (f_pre[parent] == "" ? key : f_pre[parent] "." key)
  # A repeated mapping key (a hand-edit hazard: standard YAML would last-win or
  # error) is a hard failure here — a silent merge is exactly the misparse this
  # parser exists to prevent.
  if (fullkey in keyseen) parse_err("duplicate key '" key "'", ln)
  keyseen[fullkey] = 1
  if (trim(raw) == "") {
    # open a container of not-yet-known kind
    f_ind[ns] = indent; f_pre[ns] = fullkey; f_kind[ns] = "unknown"; f_idx[ns] = 0; ns++
    return
  }
  parse_value(fullkey, raw, ln)
}

function process_line(content, indent, ln,   parent, idx, base, rest) {
  if (content == "-" || content ~ /^- /) {
    pop_to(indent)
    parent = ns - 1
    set_kind(parent, "list", ln)
    idx = f_idx[parent]; f_idx[parent] = idx + 1
    base = (f_pre[parent] == "" ? idx : f_pre[parent] "." idx)
    rest = (content == "-" ? "" : substr(content, 3))
    if (trim(rest) == "") parse_err("empty list item", ln)
    # push an item frame so the item's own keys attach under base
    f_ind[ns] = indent; f_pre[ns] = base; f_kind[ns] = "unknown"; f_idx[ns] = 0; ns++
    process_line(rest, indent + 2, ln)
    return
  }
  handle_kv(content, indent, ln)
}

BEGIN {
  # root frame: indent -1, empty prefix, a map
  ns = 1; f_ind[0] = -1; f_pre[0] = ""; f_kind[0] = "map"; f_idx[0] = 0
}

{
  line = $0
  if (line ~ /^[ \t]*$/) next                 # blank
  # A tab anywhere in the leading whitespace is out of subset (must precede the
  # [^ ] scan below, which would otherwise treat a leading tab as content).
  if (line ~ /^[ ]*\t/) parse_err("tab in indentation (use spaces)", NR)
  pos = match(line, /[^ ]/)                     # first non-space column (1-based)
  indent = pos - 1
  content = substr(line, pos)
  if (substr(content, 1, 1) == "#") next        # full-line comment
  if (indent % 2 != 0) parse_err("odd indentation (expected multiples of 2)", NR)
  process_line(content, indent, NR)
}
