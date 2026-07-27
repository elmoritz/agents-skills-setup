#!/usr/bin/env bash
# live-provider-check.sh — ask each installed assistant what it can actually see.
#
# scripts/test-adapters.sh proves the bundle matches what the vendors document.
# This proves the vendors do what they document. It copies the bundle into a
# throwaway repo and runs each assistant non-interactively:
#
#   stage 1 (discovery)   "list your skills"  → every ticket-* skill must appear
#   stage 2 (functional)  "run ticket-review" → must report that init is needed,
#                         which is only knowable by having read the skill body
#
# It calls real models, so it costs real tokens and is NOT CI-runnable. Safe by
# default: nothing runs until you pass --go.
#
#   scripts/live-provider-check.sh              # DRY: what --go would run, per CLI
#   scripts/live-provider-check.sh --go         # stage 1 against every installed CLI
#   scripts/live-provider-check.sh --go --functional   # stages 1 and 2
#   scripts/live-provider-check.sh --go --only codex   # one provider
#
# Providers with no CLI on this machine (Antigravity, Copilot cloud, IDE agent
# modes) print a manual checklist instead — record results in
# docs/platform-support.md § Verification log.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
ROOT=$PWD

MODE=preview FUNCTIONAL=0 ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --go) MODE=go; shift ;;
    --functional) FUNCTIONAL=1; shift ;;
    --only) ONLY="$2"; shift 2 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

EXPECT="ticket-init ticket-new ticket-refine ticket-pick ticket-review ticket-reject ticket-close grill-me"
DISCOVER_PROMPT="List the name of every skill available to you in this session, one name per line and nothing else. Do not read or search files; report only what is already loaded."
FUNCTIONAL_PROMPT="Use the ticket-review skill on this repository and follow it. Report exactly what it tells you to do. Do not create any files."

want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }
have() { command -v "$1" >/dev/null 2>&1; }

# --- throwaway workspace: the bundle, no config.yaml ------------------------
setup_workspace() {
  WS=$(mktemp -d)
  mkdir -p "$WS/.gemini" "$WS/.codex" "$WS/.github"
  cp -R "$ROOT/.agents" "$WS/.agents"
  cp -R "$ROOT/.gemini/." "$WS/.gemini/"
  cp -R "$ROOT/.codex/." "$WS/.codex/"
  cp -R "$ROOT/.github/agents" "$WS/.github/agents"
  cp "$ROOT/AGENTS.md" "$WS/AGENTS.md"
  rm -f "$WS/.agents/config.yaml"          # stage 2 asserts the "run init first" path
  ( cd "$WS" && git init -q && git add -A \
    && git -c user.email=probe@local -c user.name=probe commit -qm "provider probe" )
  echo "$WS"
}

report_discovery() { # report_discovery <provider> <output-file>
  local p=$1 out=$2 missing="" s
  for s in $EXPECT; do
    grep -q "$s" "$out" || missing="$missing $s"
  done
  if [ -n "$missing" ]; then
    echo "  FAIL [$p] discovery: not visible —$missing"
    echo "        (full output: $out)"
    return 1
  fi
  echo "  ok   [$p] discovery: all 8 user-invocable skills visible"
  return 0
}

report_functional() { # report_functional <provider> <output-file>
  local p=$1 out=$2
  if grep -qi "ticket-init" "$out"; then
    echo "  ok   [$p] functional: read the skill and asked for init (config-less repo)"
    return 0
  fi
  echo "  FAIL [$p] functional: never surfaced the 'run ticket-init first' path"
  echo "        (full output: $out)"
  return 1
}

run_provider() { # run_provider <name> <workspace>
  local p=$1 ws=$2 out rc=0
  out=$(mktemp "${TMPDIR:-/tmp}/provider-$p-XXXX.txt")
  case "$p" in
    codex)   ( cd "$ws" && timeout 300 codex exec --sandbox read-only "$DISCOVER_PROMPT" ) > "$out" 2>&1 || rc=$? ;;
    copilot) ( cd "$ws" && timeout 300 copilot -p "$DISCOVER_PROMPT" --allow-all-tools --no-color ) > "$out" 2>&1 || rc=$? ;;
    gemini)  ( cd "$ws" && timeout 300 gemini -p "$DISCOVER_PROMPT" ) > "$out" 2>&1 || rc=$? ;;
  esac
  [ "$rc" -eq 0 ] || echo "  warn [$p]: CLI exited $rc (output kept at $out)"
  report_discovery "$p" "$out" || FAILED=1

  [ "$FUNCTIONAL" -eq 1 ] || return 0
  out=$(mktemp "${TMPDIR:-/tmp}/provider-$p-fn-XXXX.txt"); rc=0
  case "$p" in
    codex)   ( cd "$ws" && timeout 300 codex exec --sandbox read-only "$FUNCTIONAL_PROMPT" ) > "$out" 2>&1 || rc=$? ;;
    copilot) ( cd "$ws" && timeout 300 copilot -p "$FUNCTIONAL_PROMPT" --allow-all-tools --no-color ) > "$out" 2>&1 || rc=$? ;;
    gemini)  ( cd "$ws" && timeout 300 gemini -p "$FUNCTIONAL_PROMPT" ) > "$out" 2>&1 || rc=$? ;;
  esac
  [ "$rc" -eq 0 ] || echo "  warn [$p]: CLI exited $rc (output kept at $out)"
  report_functional "$p" "$out" || FAILED=1
}

MANUAL=$(cat <<'EOF'
Manual checks — no CLI on this machine, or no headless mode:

  Antigravity (IDE or antigravity CLI)
    1. Open the probe workspace as a project.
    2. Type `/` in the agent panel — /ticket-init … /ticket-close must be listed.
    3. Run /ticket-review; it must answer "Run /ticket-init first."
    4. Ask "which subagents can you invoke?" — the five review agents must appear.

  Copilot cloud agent
    1. Push the probe workspace to a scratch GitHub repo.
    2. Open an issue: "List every skill you can see and their directories."
    3. Assign it to Copilot; the ten skills must come back from .agents/skills/.

  Copilot in VS Code / JetBrains agent mode
    1. Open the probe workspace, agent mode, same question.

Record what you find in docs/platform-support.md § Verification log.
EOF
)

if [ "$MODE" = preview ]; then
  echo "DRY RUN — nothing executed. --go runs the checks below (each costs tokens)."
  echo
  for p in codex copilot gemini; do
    want "$p" || continue
    if have "$p"; then
      echo "  would probe: $p  (stage 1$([ "$FUNCTIONAL" -eq 1 ] && echo " + stage 2"))"
    else
      echo "  skip:        $p  (not installed)"
    fi
  done
  echo
  echo "$MANUAL"
  exit 0
fi

FAILED=0
WS=$(setup_workspace)
trap 'rm -rf "$WS"' EXIT
echo "probe workspace: $WS (bundle copied, no config.yaml)"
echo

ran=0
for p in codex copilot gemini; do
  want "$p" || continue
  if have "$p"; then ran=$((ran + 1)); run_provider "$p" "$WS"; else echo "  skip [$p]: not installed"; fi
done

echo
if [ "$ran" -eq 0 ]; then
  echo "No provider CLI was available to probe."
fi
echo "$MANUAL"
echo
[ "$FAILED" -eq 0 ] || { echo "live-provider-check: FAILED"; exit 1; }
echo "live-provider-check: ok ($ran provider CLI(s) probed)"
