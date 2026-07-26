#!/usr/bin/env bash
# live-gh-check.sh — verify the github backend against a REAL throwaway GitHub
# repo: create a uniquely-named private repo + workflow labels + a few issues
# (assignee, a blocked-by pair, a milestone, a Related: line) and optionally a
# Projects v2 board, then run `te read/list/deps/milestone/projects resolve`
# LIVE against it and walk TE-004's manual Projects checklist.
#
# This is the ONE step the offline fixtures can't cover (decision 4). It is NOT
# CI-runnable and is meant to be run by a human. It touches a real account, so
# it is safe-by-default:
#
#   scripts/live-gh-check.sh                 # DRY: print exactly what --go would do
#   scripts/live-gh-check.sh --go            # create + verify (user-owned, no board)
#   scripts/live-gh-check.sh --go --projects # also create a Projects v2 board
#   scripts/live-gh-check.sh --cleanup       # delete the repo + board THIS tool made
#   [--owner <org>]                          # create under an org instead of you
#
# Safety invariants:
#   * A repo is created ONLY with a fresh, unique name pre-checked to not exist.
#   * Cleanup targets ONLY what is recorded in the run-state file and re-verifies
#     the repo carries the sentinel description this run wrote — never a name from
#     argv. Projects v2 boards live at the owner level and survive repo deletion,
#     so cleanup deletes the tracked board too.
#   * All scopes the chosen flags need are checked BEFORE the first write; a
#     failure after creation prints the exact teardown command.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
TE="$PWD/.claude/scripts/te"
STATE="$PWD/.live-gh-check.state"
SCAFFOLD="$PWD/scripts/te-scaffold.sh"

MODE=preview OWNER="" PROJECTS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --go) MODE=go; shift ;;
    --cleanup) MODE=cleanup; shift ;;
    --projects) PROJECTS=1; shift ;;
    --owner) OWNER="$2"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "live-gh-check: unknown arg: $1" >&2; exit 2 ;;
  esac
done

die() { echo "live-gh-check: $*" >&2; exit 1; }
have_gh() { command -v gh >/dev/null 2>&1 || die "gh is not installed"; }
gh_scopes() { gh auth status 2>&1 | sed -n 's/.*Token scopes: //p' | tr -d "'" | tr ',' ' '; }
has_scope() { case " $(gh_scopes) " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

require_scopes() {  # abort before any write if a needed scope is missing
  have_gh
  gh auth status >/dev/null 2>&1 || die "not logged in — run 'gh auth login'"
  local need="repo delete_repo" s missing=""
  [ "$PROJECTS" -eq 1 ] && need="$need project read:project"
  for s in $need; do
    case "$s" in read:project) has_scope project || has_scope read:project || missing="$missing project" ;;
                 *) has_scope "$s" || missing="$missing $s" ;; esac
  done
  # de-dup 'project'
  missing=$(printf '%s\n' $missing | sort -u | tr '\n' ' ')
  if [ -n "$(printf '%s' "$missing" | tr -d ' ')" ]; then
    die "missing gh scopes:$missing
  run: gh auth refresh -h github.com -s $(printf '%s' "$missing" | tr ' ' ',' | sed 's/^,//;s/,$//')"
  fi
}

# ---------------- cleanup ----------------
if [ "$MODE" = cleanup ]; then
  have_gh
  [ -f "$STATE" ] || die "no run-state file ($STATE) — nothing this tool created to clean up"
  # shellcheck disable=SC1090
  . "$STATE"
  : "${LGC_REPO:?state file missing LGC_REPO}" "${LGC_SENTINEL:?state file missing LGC_SENTINEL}"
  echo "Verifying $LGC_REPO carries this tool's sentinel before deleting…"
  desc=$(gh repo view "$LGC_REPO" --json description -q .description 2>/dev/null || true)
  if [ "$desc" != "$LGC_SENTINEL" ]; then
    die "refusing to delete $LGC_REPO — its description does not match the recorded sentinel (not created by this run, or already gone)"
  fi
  if [ "${LGC_PROJECT:-}" != "" ]; then
    echo "Deleting Projects v2 board #$LGC_PROJECT (owner ${LGC_OWNER})…"
    gh project delete "$LGC_PROJECT" --owner "$LGC_OWNER" || echo "  (board delete failed — remove it manually)"
  fi
  echo "Deleting repo $LGC_REPO…"
  gh repo delete "$LGC_REPO" --yes
  rm -f "$STATE"
  echo "cleaned up."
  exit 0
fi

# ---------------- resolve owner + a fresh, non-existent repo name ----------------
have_gh
[ -f "$STATE" ] && die "a previous run's state exists ($STATE). Run --cleanup first (or remove it if you already deleted the repo)."
gh auth status >/dev/null 2>&1 || die "not logged in — run 'gh auth login'"
[ -n "$OWNER" ] || OWNER=$(gh api user -q .login)
STAMP=$(date +%Y%m%d-%H%M%S)-$RANDOM
NAME="te-live-check-$STAMP"
REPO="$OWNER/$NAME"
SENTINEL="te-live-check sentinel $STAMP (safe to delete)"

if [ "$MODE" = preview ]; then
  cat <<EOF
DRY RUN — nothing created. With --go this tool would:
  owner:        $OWNER  $( [ "$OWNER" = "$(gh api user -q .login 2>/dev/null)" ] && echo '(you)' || echo '(ORG — double-check!)')
  repo:         $REPO   (private, description = the sentinel)
  labels:       status:{backlog,in-progress,in-review,done}, type:*, prio:*, effort:*, risk:*, milestone:v1
  milestone:    v1
  issues:       #A open (assigned to you, type:feature, prio:P2, milestone v1, body "Related: #B")
                #B open (blocked-by #A)
                #C closed as completed (to exercise stage=done)
  projects:     $( [ "$PROJECTS" -eq 1 ] && echo 'a Projects v2 board + Status/Priority/Effort/Risk fields, issues added' || echo 'skipped (pass --projects to include)')
  then:         run te read/list/deps/milestone$( [ "$PROJECTS" -eq 1 ] && echo '/projects resolve') LIVE against $REPO and print the manual Projects checklist.
  scopes:       repo, delete_repo$( [ "$PROJECTS" -eq 1 ] && echo ', project')  (checked before the first write)
Re-run with --go to execute, then --cleanup to delete everything this tool made.
EOF
  exit 0
fi

# ---------------- go ----------------
require_scopes
gh repo view "$REPO" >/dev/null 2>&1 && die "safety stop: $REPO already exists (name collision). Re-run to get a new name."

echo "Creating $REPO …"
gh repo create "$REPO" --private --description "$SENTINEL" >/dev/null
# record state IMMEDIATELY so a mid-run failure is cleanable
printf 'LGC_REPO=%s\nLGC_OWNER=%s\nLGC_SENTINEL=%q\n' "$REPO" "$OWNER" "$SENTINEL" > "$STATE"
# on any failure past here, tell the user how to tear down
trap 'echo "" >&2; echo "live-gh-check: FAILED after creating resources. Tear down with:" >&2; echo "  scripts/live-gh-check.sh --cleanup" >&2' ERR

mklabel() { gh label create "$1" --repo "$REPO" --color "$2" --force >/dev/null; }
echo "Creating labels …"
for l in backlog in-progress in-review done; do mklabel "status:$l" 888888; done
for t in feature bug tech spike; do mklabel "type:$t" 1d76db; done
for p in P0 P1 P2 P3; do mklabel "prio:$p" d93f0b; done
for e in S M L XL; do mklabel "effort:$e" fef2c0; done
for r in low med high; do mklabel "risk:$r" c2e0c6; done
mklabel "milestone:v1" 0e8a16

echo "Creating milestone v1 …"
gh api "repos/$REPO/milestones" -f title=v1 -f state=open >/dev/null 2>&1 || true

echo "Creating issues …"
A=$(gh issue create --repo "$REPO" --title "Blocker task" \
      --body "The blocker." --label status:in-progress --label type:feature --label prio:P2 \
      --assignee @me --milestone v1 | sed 's#.*/##')
B=$(gh issue create --repo "$REPO" --title "Dependent task" \
      --body "Related: #$A" --label status:backlog --label type:tech --label prio:P1 | sed 's#.*/##')
gh issue edit "$B" --repo "$REPO" --add-blocked-by "$A" >/dev/null 2>&1 \
  || echo "  (--add-blocked-by needs gh >= 2.94; blockedBy left unset)"
C=$(gh issue create --repo "$REPO" --title "Shipped task" \
      --body "Done." --label type:tech | sed 's#.*/##')
gh issue close "$C" --repo "$REPO" --reason completed >/dev/null

PROJ=""
if [ "$PROJECTS" -eq 1 ]; then
  echo "Creating Projects v2 board …"
  PROJ=$(gh project create --owner "$OWNER" --title "te-live-check $STAMP" --format json -q .number)
  printf 'LGC_PROJECT=%s\n' "$PROJ" >> "$STATE"
  for f in Priority Effort Risk; do
    gh project field-create "$PROJ" --owner "$OWNER" --name "$f" --data-type SINGLE_SELECT \
      --single-select-options "P0,P1,P2,P3" >/dev/null 2>&1 || true
  done
  gh project item-add "$PROJ" --owner "$OWNER" --url "https://github.com/$REPO/issues/$A" >/dev/null 2>&1 || true
  gh project item-add "$PROJ" --owner "$OWNER" --url "https://github.com/$REPO/issues/$B" >/dev/null 2>&1 || true
  echo "  NOTE: set the board Status/Priority/Effort/Risk on #$A/#$B in the UI, then re-run the read below to verify board-first resolution."
fi

# ---------------- scaffold a config pointing at the real repo, run te LIVE ------
WORK=$(mktemp -d)
"$SCAFFOLD" --out "$WORK" --backend gh --milestones auto \
  $( [ "$PROJECTS" -eq 1 ] && printf -- '--projects --project-number %s --project-owner %s' "$PROJ" "$OWNER") \
  --repo "$REPO" --no-validate >/dev/null
echo ""
echo "===== LIVE te against $REPO ====="
run() { echo "--- te $* ---"; ( cd "$WORK" && "$TE" "$@" ) || echo "  (te exited nonzero)"; echo; }
run config validate >/dev/null 2>&1 && echo "config validate: ok" || echo "config validate: FAILED"; echo
run read "$A"
run read "$C"                         # expect stage=done, closed_as=shipped
run list in_progress
run deps check "$B" --depends-on "$A" # expect ok (acyclic)
run milestone scan
[ "$PROJECTS" -eq 1 ] && run projects resolve

cat <<EOF
===== manual Projects checklist (record the results) =====
- [ ] te read #$A: stage=in-progress, type=feature, claimed_by=you, claimed_at set, depends_on empty, related=$B
- [ ] te read #$B: depends_on=$A (from blockedBy), related empty
- [ ] te read #$C: stage=done, closed_as=shipped (closed-state wins)
- [ ] te list in_progress: exactly #$A
- [ ] te deps check #$B --depends-on #$A: ok=true; then try a real cycle to see the chain
- [ ] te milestone scan: v1 with open/closed counts and drift flag
$( [ "$PROJECTS" -eq 1 ] && printf -- '- [ ] set board fields on #%s, re-run te read #%s: priority/effort/risk come from the BOARD (board-first)\n- [ ] te projects resolve: resolves the Status field id + option map\n' "$A" "$A")
When done:  scripts/live-gh-check.sh --cleanup
EOF
trap - ERR
