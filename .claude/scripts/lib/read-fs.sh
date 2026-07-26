# read-fs.sh — the filesystem read path (TE-003): te read / te list / te milestone
# scan. Sourced by te. Emits the uniform field view frozen here for TE-004.
# bash 3.2 clean; frontmatter via fm.awk (opaque), ledger via config.awk.

TAB=$(printf '\t')

# --- small readers over flattened records (all return 0 so `x=$(...)` is safe
#     under set -e even when the key is absent) --------------------------------
_fmv() {  # value of frontmatter key $1 from $TE_TMPD/fmflat ("" if absent)
  local k=$1 kk vv
  while IFS="$TAB" read -r kk vv; do
    [ "$kk" = "$k" ] && { printf '%s\n' "$vv"; return 0; }
  done < "$TE_TMPD/fmflat"
  return 0
}
_fm_has() {  # true iff frontmatter carries key $1
  local k=$1 kk vv
  while IFS="$TAB" read -r kk vv; do
    [ "$kk" = "$k" ] && return 0
  done < "$TE_TMPD/fmflat"
  return 1
}
_nn() { [ "$1" = "null" ] && printf '' || printf '%s' "$1"; }  # null -> empty

_ledger_scalar_for() {  # value of <id>.<field> in $TE_TMPD/ledger ("" if absent)
  local id=$1 field=$2 tag key val rest
  while IFS="$TAB" read -r tag key val rest; do
    [ "$tag" = "V" ] || continue
    [ "$key" = "$id.$field" ] && { printf '%s\n' "$val"; return 0; }
  done < "$TE_TMPD/ledger"
  return 0
}
_ledger_list_for() {  # comma-joined <id>.<field>.N values ("" if none)
  local id=$1 field=$2 tag key val rest out=""
  while IFS="$TAB" read -r tag key val rest; do
    [ "$tag" = "V" ] || continue
    case "$key" in "$id.$field".[0-9]*) out="${out:+$out,}$val" ;; esac
  done < "$TE_TMPD/ledger"
  printf '%s\n' "$out"
  return 0
}

# TSV lookups (pure bash — the "no embedded awk" rule keeps awk in -f files, and
# -v would mangle backslashes in user-derived keys).
_tsv_get() {  # value of column 2 where column 1 == $2, in TSV file $1 ("" if none)
  local file=$1 want=$2 k v
  while IFS="$TAB" read -r k v; do
    [ "$k" = "$want" ] && { printf '%s\n' "$v"; return 0; }
  done < "$file"
  return 0
}
_tsv_get3() {  # column $3 (2 or 3) where column 1 == $2, in a 3-col TSV file $1
  local file=$1 want=$2 col=$3 c1 c2 c3
  while IFS="$TAB" read -r c1 c2 c3; do
    if [ "$c1" = "$want" ]; then
      [ "$col" = "2" ] && printf '%s\n' "$c2" || printf '%s\n' "$c3"
      return 0
    fi
  done < "$file"
  return 0
}

# id<TAB>stage for every ticket file across the stage folders (one scan).
_fs_id_stage_index() {
  local root prefix i folder skey f base num
  root=$(cfg_get backend.filesystem.root)
  prefix=$(cfg_get ticket_id.prefix)
  i=0
  while folder=$(cfg_get "lifecycle.stages.$i.filesystem.folder"); do
    skey=$(cfg_get "lifecycle.stages.$i.key")
    if [ -d "$root/$folder" ]; then
      for f in "$root/$folder/$prefix"-*.md; do
        [ -f "$f" ] || continue
        base=$(basename "$f"); num=${base#"$prefix"-}; num=${num%%-*}; num=${num%.md}
        case "$num" in ''|*[!0-9]*) continue ;; esac
        printf '%s-%s\t%s\n' "$prefix" "$num" "$skey"
      done
    fi
    i=$((i + 1))
  done
  return 0
}

_stage_folder() {  # filesystem.folder for stage key $1
  local want=$1 i=0 skey
  while skey=$(cfg_get "lifecycle.stages.$i.key"); do
    [ "$skey" = "$want" ] && { cfg_get "lifecycle.stages.$i.filesystem.folder"; return 0; }
    i=$((i + 1))
  done
  return 1
}

# stagekey -> role, from the resolved roles.* map (one line per declared role)
_role_of_stage() {  # $1 stagekey -> role name ("" if none)
  local want=$1 r v
  for r in inbox pickable in_progress review terminal; do
    v=$(cfg_get "roles.$r" || true)
    [ -n "$v" ] && [ "$v" = "$want" ] && { printf '%s\n' "$r"; return 0; }
  done
  return 0
}

# --- te read <id> [config] ---------------------------------------------------
cmd_read() {
  local id="" cfg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) shift ;;
      *) if [ -z "$id" ]; then id="$1"; else cfg="$1"; fi; shift ;;
    esac
  done
  [ -n "$id" ] || { te_emit_fail "read" "no id given" "usage: te read <id>"; return 1; }
  load_config "$cfg" || return 1
  local backend; backend=$(cfg_get backend.type)
  if [ "$backend" != "filesystem" ]; then
    te_emit_fail "read" "te read on the $backend backend lands in TE-004" "use the filesystem backend"
    return 1
  fi
  local root prefix i=0 folder skey file="" stage=""
  root=$(cfg_get backend.filesystem.root); prefix=$(cfg_get ticket_id.prefix)
  while folder=$(cfg_get "lifecycle.stages.$i.filesystem.folder"); do
    skey=$(cfg_get "lifecycle.stages.$i.key")
    for f in "$root/$folder/$id"-*.md; do
      [ -f "$f" ] || continue
      file="$f"; stage="$skey"; break
    done
    [ -n "$file" ] && break
    i=$((i + 1))
  done
  if [ -z "$file" ]; then
    printf 'ok=false\nreason=not found\n'   # § read_artifact's documented shape
    return 1
  fi
  # slice frontmatter (sed) and body (tail) — body stays byte-exact, no $()
  local fmend bodystart
  fmend=$(awk -f "$TE_LIB/split-fm.awk" "$file")
  if [ -n "$fmend" ]; then
    sed -n "2,$((fmend - 1))p" "$file" > "$TE_TMPD/fmraw"
    bodystart=$((fmend + 1))
  else
    : > "$TE_TMPD/fmraw"; bodystart=1
  fi
  awk -f "$TE_LIB/fm.awk" "$TE_TMPD/fmraw" > "$TE_TMPD/fmflat"
  _ledger_flatten "$(_ledger_path)" || return 1

  local deps rel mil drift="" k
  deps=$(_ledger_list_for "$id" depends_on)
  rel=$(_ledger_list_for "$id" related)
  mil=$(_nn "$(_ledger_scalar_for "$id" milestone)")
  for k in depends_on related milestone; do
    _fm_has "$k" && drift="${drift:+$drift,}$k"
  done

  printf 'id=%s\n' "$id"
  printf 'stage=%s\n' "$stage"
  printf 'type=%s\n' "$(_fmv type)"
  printf 'title=%s\n' "$(_fmv title)"
  printf 'priority=%s\n' "$(_fmv priority)"
  printf 'effort=%s\n' "$(_fmv effort)"
  printf 'risk=%s\n' "$(_fmv risk)"
  printf 'milestone=%s\n' "$mil"
  printf 'created=%s\n' "$(_fmv created)"
  printf 'claimed_by=%s\n' "$(_nn "$(_fmv claimed_by)")"
  printf 'claimed_at=%s\n' "$(_nn "$(_fmv claimed_at)")"
  printf 'closed_as=%s\n' "$(_nn "$(_fmv closed_as)")"
  printf 'depends_on=%s\n' "$deps"
  printf 'related=%s\n' "$rel"
  [ -n "$drift" ] && printf 'drift=%s\n' "$drift"
  printf '%s\n' "---BODY---"
  tail -n +"$bodystart" "$file"
  return 0
}

# --- te list <role> [filters] [config] ---------------------------------------
cmd_list() {
  local role="" cfg="" f_priority="" f_effort="" f_type="" f_milestone="" depsat=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --priority)  f_priority="${2:-}"; shift 2 ;;
      --effort)    f_effort="${2:-}"; shift 2 ;;
      --type)      f_type="${2:-}"; shift 2 ;;
      --milestone) f_milestone="${2:-}"; shift 2 ;;
      --depends-satisfied) depsat=1; shift ;;
      --dry-run) shift ;;
      *) if [ -z "$role" ]; then role="$1"; else cfg="$1"; fi; shift ;;
    esac
  done
  [ -n "$role" ] || { te_emit_fail "list" "no role given" "usage: te list <role> [filters]"; return 1; }
  load_config "$cfg" || return 1
  local backend; backend=$(cfg_get backend.type)
  if [ "$backend" != "filesystem" ]; then
    te_emit_fail "list" "te list on the $backend backend lands in TE-004" "use the filesystem backend"
    return 1
  fi
  local stagekey; stagekey=$(cfg_get "roles.$role" || true)
  if [ -z "$stagekey" ]; then
    te_emit_fail "list" "no stage carries the role '$role'" "check the role name (inbox/pickable/in_progress/review/terminal)"
    return 1
  fi
  local root folder; root=$(cfg_get backend.filesystem.root); folder=$(_stage_folder "$stagekey")
  [ -d "$root/$folder" ] || return 0   # empty/absent stage -> no output, exit 0

  _ledger_flatten "$(_ledger_path)" || return 1
  _fs_id_stage_index > "$TE_TMPD/idstage"
  local termkey; termkey=$(cfg_get roles.terminal)
  local prefix f base num id first=1
  prefix=$(cfg_get ticket_id.prefix)
  for f in "$root/$folder/$prefix"-*.md; do
    [ -f "$f" ] || continue
    base=$(basename "$f"); num=${base#"$prefix"-}; num=${num%%-*}; num=${num%.md}
    case "$num" in ''|*[!0-9]*) continue ;; esac
    id="$prefix-$num"
    # frontmatter
    local fmend
    fmend=$(awk -f "$TE_LIB/split-fm.awk" "$f")
    if [ -n "$fmend" ]; then sed -n "2,$((fmend - 1))p" "$f" > "$TE_TMPD/fmraw"; else : > "$TE_TMPD/fmraw"; fi
    awk -f "$TE_LIB/fm.awk" "$TE_TMPD/fmraw" > "$TE_TMPD/fmflat"
    local p e t c cby clat mil
    p=$(_fmv priority); e=$(_fmv effort); t=$(_fmv type); c=$(_fmv created)
    cby=$(_nn "$(_fmv claimed_by)"); clat=$(_nn "$(_fmv claimed_at)")
    mil=$(_nn "$(_ledger_scalar_for "$id" milestone)")
    # filters
    [ -n "$f_priority" ] && [ "$f_priority" != "$p" ] && continue
    [ -n "$f_effort" ] && [ "$f_effort" != "$e" ] && continue
    [ -n "$f_type" ] && [ "$f_type" != "$t" ] && continue
    [ -n "$f_milestone" ] && [ "$f_milestone" != "$mil" ] && continue
    if [ "$depsat" -eq 1 ]; then
      local dep depstage skip=0
      for dep in $(_ledger_list_for "$id" depends_on | tr ',' ' '); do
        [ -n "$dep" ] || continue
        depstage=$(_tsv_get "$TE_TMPD/idstage" "$dep")
        [ "$depstage" = "$termkey" ] || { skip=1; break; }
      done
      [ "$skip" -eq 1 ] && continue
    fi
    [ "$first" -eq 1 ] || printf '\n'
    first=0
    printf 'id=%s\ntitle=%s\npriority=%s\neffort=%s\ntype=%s\nmilestone=%s\nclaimed_by=%s\nclaimed_at=%s\ncreated=%s\n' \
      "$id" "$(_fmv title)" "$p" "$e" "$t" "$mil" "$cby" "$clat" "$c"
  done
  return 0
}

# --- te milestone scan [--version V] [config] --------------------------------
cmd_milestone_scan() {
  local want="" cfg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --version) want="${2:-}"; shift 2 ;;
      --dry-run) shift ;;
      *) cfg="$1"; shift ;;
    esac
  done
  load_config "$cfg" || return 1
  local backend strat; backend=$(cfg_get backend.type); strat=$(cfg_get milestones.strategy)
  [ "$strat" = "auto" ] && strat=$([ "$backend" = "filesystem" ] && echo trackers || echo native)
  if [ "$backend" != "filesystem" ]; then
    echo "ok=true"; echo "note=github milestone scan (native/labels) lands in TE-004"
    return 0
  fi
  if [ "$strat" = "none" ] || [ "$strat" = "native" ]; then
    return 0   # nothing to scan on filesystem
  fi

  _ledger_flatten "$(_ledger_path)" || return 1
  _fs_id_stage_index > "$TE_TMPD/idstage"
  # id<TAB>version from the ledger, joined to stage from the index
  : > "$TE_TMPD/msve"
  local tag key val rest id ver stage role
  while IFS="$TAB" read -r tag key val rest; do
    [ "$tag" = "V" ] || continue
    case "$key" in *.milestone) id=${key%.milestone}; printf '%s\t%s\n' "$id" "$val" >> "$TE_TMPD/msve" ;; esac
  done < "$TE_TMPD/ledger"

  if [ "$strat" = "labels" ]; then
    # distribution only, no tracker/drift
    local versions v n
    versions=$(cut -f2 "$TE_TMPD/msve" | sort -u)
    for v in $versions; do
      { [ -n "$want" ] && [ "$want" != "$v" ]; } && continue
      n=$(cut -f2 "$TE_TMPD/msve" | grep -Fxc "$v" || true)
      printf 'version=%s\ncount=%s\n\n' "$v" "$n"
    done
    return 0
  fi

  # trackers: read tracker files, per version status+folder, distribution, drift
  local pa sh; pa=$(cfg_get milestones.trackers.planned_active_folder || echo milestone)
  sh=$(cfg_get milestones.trackers.shipped_folder || echo done)
  local root; root=$(cfg_get backend.filesystem.root)
  : > "$TE_TMPD/trackers"   # version<TAB>status<TAB>folder
  local tf folder_name f fmend tver tstat ttype
  for tf in "$pa" "$sh"; do
    folder_name="$tf"
    [ -d "$root/$tf" ] || continue
    for f in "$root/$tf"/*.md; do
      [ -f "$f" ] || continue
      fmend=$(awk -f "$TE_LIB/split-fm.awk" "$f")
      [ -n "$fmend" ] || continue
      sed -n "2,$((fmend - 1))p" "$f" > "$TE_TMPD/fmraw"
      awk -f "$TE_LIB/fm.awk" "$TE_TMPD/fmraw" > "$TE_TMPD/fmflat"
      ttype=$(_fmv type); [ "$ttype" = "milestone" ] || continue
      tver=$(_fmv version); tstat=$(_fmv status)
      [ -n "$tver" ] && printf '%s\t%s\t%s\n' "$tver" "$tstat" "$folder_name" >> "$TE_TMPD/trackers"
    done
  done

  # union of versions across trackers and ticket assignments
  local versions v
  versions=$( { cut -f1 "$TE_TMPD/trackers"; cut -f2 "$TE_TMPD/msve"; } | sort -u )
  for v in $versions; do
    [ -n "$v" ] || continue
    { [ -n "$want" ] && [ "$want" != "$v" ]; } && continue
    local tstatus tfolder cin cp ci cr ct total started expstat expfolder drift
    tstatus=$(_tsv_get3 "$TE_TMPD/trackers" "$v" 2)
    tfolder=$(_tsv_get3 "$TE_TMPD/trackers" "$v" 3)
    cin=0; cp=0; ci=0; cr=0; ct=0
    # count tickets of this version per role (inbox kept distinct from pickable)
    while IFS="$TAB" read -r id ver; do
      [ "$ver" = "$v" ] || continue
      stage=$(_tsv_get "$TE_TMPD/idstage" "$id")
      role=$(_role_of_stage "$stage")
      case "$role" in
        inbox)       cin=$((cin + 1)) ;;
        pickable)    cp=$((cp + 1)) ;;
        in_progress) ci=$((ci + 1)) ;;
        review)      cr=$((cr + 1)) ;;
        terminal)    ct=$((ct + 1)) ;;
      esac
    done < "$TE_TMPD/msve"
    total=$((cin + cp + ci + cr + ct)); started=$((ci + cr + ct))
    if [ "$total" -ge 1 ] && [ "$ct" -eq "$total" ]; then expstat=shipped
    elif [ "$started" -ge 1 ] && [ "$ct" -lt "$total" ]; then expstat=active
    else expstat=planned
    fi
    [ "$expstat" = "shipped" ] && expfolder="$sh" || expfolder="$pa"
    drift=false
    if [ -n "$tstatus" ] && [ "$tstatus" != "$expstat" ]; then drift=true; fi
    if [ -n "$tfolder" ] && [ "$tfolder" != "$expfolder" ]; then drift=true; fi
    printf 'version=%s\ntracker_status=%s\ntracker_folder=%s\nexpected_status=%s\nexpected_folder=%s\ndrift=%s\ncount.inbox=%s\ncount.pickable=%s\ncount.in_progress=%s\ncount.review=%s\ncount.terminal=%s\n\n' \
      "$v" "$tstatus" "$tfolder" "$expstat" "$expfolder" "$drift" "$cin" "$cp" "$ci" "$cr" "$ct"
  done
  return 0
}
