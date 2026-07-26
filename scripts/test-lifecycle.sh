#!/usr/bin/env bash
# test-lifecycle.sh — drive one ticket project through the FULL /ticket:* workflow
# on a real (temp) filesystem git repo, then re-validate with te after every
# event. This exercises the ticket-engine WRITE path — which ships as prose
# (model-executed, decision 2) — by performing exactly the documented steps:
#
#   § Transition primitives (filesystem): 1) git mv src->dst  2) edit frontmatter
#   (or the ledger for depends_on/related/milestone)  3) git add  4) run
#   verification.pre_close_command on a terminal transition and stage what it
#   touches  5) commit with commits.<event> (rendered by `te msg`, via a HEREDOC
#   so hostile titles survive).
#   Hard rules: git mv BEFORE the frontmatter edit (so git records a rename and
#   `git log --follow` survives); ledger edits ride the event's commit; one event
#   = one commit; never amend; never re-issue an ID.
#
# The harness is a faithful test executor of that prose, NOT the shipped engine.
# After each event it asserts te reads the new state, config+ledger stay valid,
# exactly one commit was added, the commit subject matches commits.<event>, and
# move events record a rename. Offline / CI-runnable (filesystem backend). The
# live github lifecycle is scripts/live-gh-check.sh.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
TE="$PWD/.claude/scripts/te"
SCAFFOLD="$PWD/scripts/te-scaffold.sh"
ROOT=proj
fail=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
"$SCAFFOLD" --out "$WORK" --backend fs --milestones auto --inbox --no-validate >/dev/null
cd "$WORK"
git init -q
git config user.name "Lifecycle Test"; git config user.email "lifecycle@test.local"
git config commit.gpgsign false
# a header-only ledger is a valid empty ledger; drop the {} stub before appending
sed -i.bak '/^{}$/d' "$ROOT/.ledger.yaml" && rm -f "$ROOT/.ledger.yaml.bak"
# exercise § Transition primitives step 4: a real pre_close_command
sed -i.bak 's#^  pre_close_command: null#  pre_close_command: touch proj/.preclose-ran#' "$ROOT/.claude/config.yaml" 2>/dev/null || true
sed -i.bak 's#^  pre_close_command: null#  pre_close_command: touch proj/.preclose-ran#' .claude/config.yaml && rm -f .claude/config.yaml.bak
# a v1 milestone tracker, initially active
cat > "$ROOT/milestone/v1.md" <<'EOF'
---
type: milestone
version: v1
status: active
---
v1 tracker
EOF
git add -A && git commit -qm "init: scaffold lifecycle test project"

USER_NAME=$(git config user.name)
PREV=$(git rev-list --count HEAD)

say() { printf '\n== %s ==\n' "$*"; }
bad() { echo "  FAIL: $*"; fail=1; }
fm_set()  { sed -i.bak "s#^$2: .*#$2: $3#" "$1" && rm -f "$1.bak"; }   # $1 file $2 key $3 val
file_of() { set -- "$ROOT/$1/$2-"*.md; [ -f "$1" ] && printf '%s\n' "$1" || { bad "file_of: no file for $2"; printf '/nonexistent\n'; }; }

# emit the event commit; message rendered by te msg, committed via HEREDOC so a
# title with quotes/$ survives (§ Message formatting).
commit_event() {  # event id title [target]
  local event=$1 id=$2 title=$3 target=${4:-} msg
  msg=$("$TE" msg "$event" --id "$id" --title "$title" ${target:+--target-id "$target"})
  git commit -q -F - <<EOF
$msg
EOF
}

assert_one_commit() { local now; now=$(git rev-list --count HEAD); [ "$now" -eq $((PREV + 1)) ] || bad "$1: expected +1 commit, got $((now - PREV))"; PREV=$now; }
assert_subject()    { local want=$1 got; got=$(git log -1 --format=%s); [ "$got" = "$want" ] || bad "commit subject: want '$want' got '$got'"; }
assert_rename()     { git diff-tree --no-commit-id --name-status -M -r HEAD | grep -q '^R' || bad "$1: event commit recorded no rename (git mv missing — git log --follow would break)"; }
assert_valid()      { "$TE" config validate >/dev/null 2>&1 || bad "$1: config invalid"; "$TE" ledger validate >/dev/null 2>&1 || bad "$1: ledger invalid"; }
assert_field()      { local id=$1 key=$2 want=$3 got; got=$("$TE" read "$id" 2>/dev/null | sed -n "s/^$key=//p" | head -1); [ "$got" = "$want" ] || bad "read $id: $key want '$want' got '$got'"; }
assert_body_has()   { local id=$1 want=$2; case "$("$TE" read "$id" 2>/dev/null)" in *"$want"*) ;; *) bad "read $id: body/fields lack '$want'" ;; esac; }
assert_listed()     { local role=$1 id=$2 flag=${3:-}; case "$("$TE" list "$role" $flag 2>/dev/null)" in *"id=$id"*) ;; *) bad "list $role $flag: expected $id" ;; esac; }
assert_unlisted()   { local role=$1 id=$2 flag=${3:-}; case "$("$TE" list "$role" $flag 2>/dev/null)" in *"id=$id"*) bad "list $role $flag: $id should be absent" ;; esac; }

# --- create_artifact: file + ledger entry, one commit. Inbox uses `capture`. ---
new_ticket() {  # id title stage-folder depends-csv event
  local id=$1 title=$2 folder=$3 deps=${4:-} event=${5:-new} slug
  slug=$("$TE" slug "$title")
  cat > "$ROOT/$folder/$id-$slug.md" <<TICKET
---
type: tech
title: $title
priority: P2
effort: M
risk: low
created: 2026-01-01
claimed_by: null
claimed_at: null
closed_as: null
---
## goal
body-of-$id marker
## approach
a
## verification
v
TICKET
  # ledger entry: ledger-resident fields only; inbox tickets carry no milestone yet
  { printf '%s:\n' "$id"
    [ -n "$deps" ] && printf '  depends_on: [%s]\n' "$deps"
    [ "$folder" != inbox ] && printf '  milestone: v1\n'
  } >> "$ROOT/.ledger.yaml"
  git add "$ROOT/$folder/$id-$slug.md" "$ROOT/.ledger.yaml"
  commit_event "$event" "$id" "$title"
}
move() { local id=$1 from=$2 to=$3 f base; f=$(file_of "$from" "$id"); base=$(basename "$f"); git mv "$ROOT/$from/$base" "$ROOT/$to/$base"; MOVED="$ROOT/$to/$base"; }
# promote a ledger-resident field on refine (inbox->backlog gets its milestone)

say "new TE-001 (dependency) + TE-002 (main, depends on TE-001, hostile title)"
new_ticket TE-001 "Dependency task" backlog
assert_one_commit new-1; assert_subject "ticket: new TE-001 Dependency task"; assert_valid new-1
T2_TITLE='Main $VAR "quoted" task'
new_ticket TE-002 "$T2_TITLE" backlog TE-001
assert_one_commit new-2; assert_subject "ticket: new TE-002 $T2_TITLE"; assert_valid new-2
assert_field TE-002 title "$T2_TITLE"          # hostile title round-trips through msg + frontmatter
assert_field TE-001 stage backlog
assert_field TE-002 depends_on TE-001
assert_listed pickable TE-001; assert_listed pickable TE-002
assert_listed pickable TE-001 --depends-satisfied
assert_unlisted pickable TE-002 --depends-satisfied

say "claim TE-001 (backlog -> in-progress)"
move TE-001 backlog in-progress
fm_set "$MOVED" claimed_by "$USER_NAME"; fm_set "$MOVED" claimed_at "2026-01-02T09:00:00Z"
git add "$MOVED"; commit_event claim TE-001 "Dependency task"
assert_one_commit claim; assert_subject "ticket: claim TE-001 Dependency task"; assert_rename claim; assert_valid claim
assert_field TE-001 stage in-progress; assert_field TE-001 claimed_by "$USER_NAME"; assert_field TE-001 claimed_at "2026-01-02T09:00:00Z"

say "review TE-001 (-> in-review) then reject (-> in-progress)"
move TE-001 in-progress in-review; git add "$MOVED"; commit_event review TE-001 "Dependency task"
assert_one_commit review; assert_subject "ticket: review TE-001 Dependency task"; assert_rename review; assert_field TE-001 stage in-review
move TE-001 in-review in-progress; git add "$MOVED"; commit_event reject TE-001 "Dependency task"
assert_one_commit reject; assert_subject "ticket: reject TE-001 Dependency task"; assert_field TE-001 stage in-progress

say "close TE-001 (-> done, closed_as=shipped; pre_close_command runs, step 4)"
move TE-001 in-progress done; fm_set "$MOVED" closed_as shipped
touch proj/.preclose-ran                      # step 4: run pre_close_command, stage what it touches
git add "$MOVED" proj/.preclose-ran; commit_event done TE-001 "Dependency task"
assert_one_commit done; assert_subject "ticket: done TE-001 Dependency task"; assert_rename done; assert_valid done
assert_field TE-001 stage done; assert_field TE-001 closed_as shipped
[ -f proj/.preclose-ran ] || bad "pre_close_command did not run"
git ls-files --error-unmatch proj/.preclose-ran >/dev/null 2>&1 || bad "pre_close output not staged into the terminal commit"
assert_unlisted pickable TE-001
assert_listed pickable TE-002 --depends-satisfied

say "claim TE-002 then abandon (-> backlog, claim cleared)"
move TE-002 backlog in-progress; fm_set "$MOVED" claimed_by "$USER_NAME"; fm_set "$MOVED" claimed_at "2026-01-03T09:00:00Z"
git add "$MOVED"; commit_event claim TE-002 "$T2_TITLE"; assert_one_commit claim-2; assert_subject "ticket: claim TE-002 $T2_TITLE"
move TE-002 in-progress backlog; fm_set "$MOVED" claimed_by null; fm_set "$MOVED" claimed_at null
git add "$MOVED"; commit_event abandon TE-002 "$T2_TITLE"; assert_one_commit abandon; assert_subject "ticket: abandon TE-002 $T2_TITLE"; assert_rename abandon
assert_field TE-002 stage backlog; assert_field TE-002 claimed_by ""; assert_field TE-002 claimed_at ""

say "refine TE-003 (capture to inbox -> refine to backlog)"
new_ticket TE-003 "Refined task" inbox "" capture
assert_one_commit capture; assert_subject "ticket: capture TE-003 Refined task"
move TE-003 inbox backlog; git add "$MOVED"; commit_event refine TE-003 "Refined task"
assert_one_commit refine; assert_subject "ticket: refine TE-003 Refined task"; assert_rename refine; assert_field TE-003 stage backlog

say "fold TE-004 into TE-002 (source body merged verbatim; source closed duplicate)"
new_ticket TE-004 "Duplicate task" inbox "" capture; assert_one_commit capture-2
t=$(file_of backlog TE-002)
{ printf '\n## Folded notes\n'; sed -n '/^---$/,/^---$/!p' "$(file_of inbox TE-004)"; } >> "$t"
git add "$t"; commit_event update TE-002 "$T2_TITLE"; assert_one_commit fold-update; assert_subject "ticket: update TE-002 $T2_TITLE"
assert_body_has TE-002 "body-of-TE-004 marker"      # source body actually merged (not just the header)
move TE-004 inbox done; fm_set "$MOVED" closed_as duplicate
git add "$MOVED"; commit_event fold TE-004 "Duplicate task" TE-002
assert_one_commit fold-close; assert_subject "ticket: fold TE-004 into TE-002"; assert_rename fold-close; assert_valid fold
assert_field TE-004 stage done; assert_field TE-004 closed_as duplicate

say "wontfix a fresh ticket (-> done, closed_as=wontfix)"
new_ticket TE-005 "Wontfix task" backlog; assert_one_commit new-5
move TE-005 backlog done; fm_set "$MOVED" closed_as wontfix
git add "$MOVED"; commit_event wontfix TE-005 "Wontfix task"
assert_one_commit wontfix; assert_subject "ticket: wontfix TE-005 Wontfix task"; assert_valid wontfix
assert_field TE-005 closed_as wontfix

say "milestone-flip v1 (active -> shipped once every v1 ticket is terminal)"
for id in TE-002 TE-003; do
  move "$id" backlog done; fm_set "$MOVED" closed_as shipped; git add "$MOVED"; commit_event done "$id" "x"; assert_one_commit "done-$id"
done
case "$("$TE" milestone scan --version v1)" in *drift=true*) ;; *) bad "milestone: expected drift before flip" ;; esac
git mv "$ROOT/milestone/v1.md" "$ROOT/done/v1.md"; fm_set "$ROOT/done/v1.md" status shipped
git add "$ROOT/done/v1.md"
msg=$("$TE" msg milestone_flip --id v1 --title v1 --status shipped --version v1 --reason "all shipped")
git commit -q -F - <<EOF
$msg
EOF
assert_one_commit milestone-flip; assert_subject "milestone: shipped v1 — all shipped"; assert_rename milestone-flip
case "$("$TE" milestone scan --version v1)" in *drift=false*) ;; *) bad "milestone: still drifting after flip" ;; esac

say "final: full validation + exact commit count (init + 1 per event)"
assert_valid final
# init + new×3(001,002,005) + capture×2(003,004) + claim×2 + review + reject + abandon
# + done(001) + refine + fold-update + fold-close + wontfix + done×2(002,003) + flip = 19
got=$(git rev-list --count HEAD)
[ "$got" -eq 19 ] || bad "expected exactly 19 commits (init + one per event), got $got"

if [ "$fail" -ne 0 ]; then echo; echo "test-lifecycle: FAIL" >&2; exit 1; fi
echo; echo "test-lifecycle: ok (new/capture/refine/claim/review/reject/abandon/close/fold/wontfix/milestone-flip — renames, subjects, pre_close & state all re-validated)"
