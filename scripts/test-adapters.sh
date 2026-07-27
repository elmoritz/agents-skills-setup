#!/usr/bin/env bash
# test-adapters.sh — assert the bundle satisfies what EVERY supported provider
# documents it needs, without calling a single model.
#
# Discovery working once on one machine proves nothing durable: a renamed skill,
# a hand-edited router, a workflow file that grew past Antigravity's cap, or a
# TOML agent missing `developer_instructions` all break exactly one provider and
# stay invisible to the other suites. Each check below encodes a documented
# vendor requirement (see docs/platform-support.md for the sources), so a
# regression names the provider it breaks.
#
# Offline, deterministic, CI-runnable. The live counterpart — actually asking
# each installed assistant what it can see — is scripts/live-provider-check.sh.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

fail=0 n=0
BAD() { echo "  FAIL [$1]: $2"; fail=1; }
chk() { n=$((n + 1)); }

# YAML frontmatter scalar, single-line values only.
fm() { # fm <file> <key>
  awk -v key="$2" '
    NR == 1 && $0 == "---" { inside = 1; next }
    inside && $0 == "---" { exit }
    inside { k = $0; sub(/:.*/, "", k)
             if (k == key) { v = $0; sub(/^[^:]*:[ \t]*/, "", v); print v; exit } }
  ' "$1"
}
has_line() { grep -q "$2" "$1" 2>/dev/null; }
size()     { wc -c < "$1" | tr -d ' '; }

SKILLS=$(ls -d .agents/skills/*/ 2>/dev/null | sed 's|.*/skills/||; s|/$||')
AGENTS=$(ls .agents/agents/*.md 2>/dev/null | sed 's|.*/||; s|\.md$||')
PUBLIC=""
for s in $SKILLS; do
  [ "$(fm ".agents/skills/$s/SKILL.md" user-invocable)" = "false" ] || PUBLIC="$PUBLIC $s"
done

echo "skills: $(echo "$SKILLS" | wc -w | tr -d ' ') ($(echo "$PUBLIC" | wc -w | tr -d ' ') user-invocable) · review agents: $(echo "$AGENTS" | wc -w | tr -d ' ')"

# --- Agent Skills standard: every provider reads the same shape --------------
# A skill is <dir>/SKILL.md with `name` + `description`; Gemini CLI and Codex
# both refuse anything nested deeper than one directory.
for s in $SKILLS; do
  f=".agents/skills/$s/SKILL.md"
  chk; [ -f "$f" ] || BAD "skills" "$s has no SKILL.md at depth 1"
  chk; [ -n "$(fm "$f" name)" ] || BAD "skills" "$s: frontmatter lacks name"
  chk; [ -n "$(fm "$f" description)" ] || BAD "skills" "$s: frontmatter lacks description (drives implicit activation everywhere)"
  chk; [ "$(fm "$f" name)" = "$s" ] || BAD "skills" "$s: frontmatter name '$(fm "$f" name)' != directory name (Codex/Copilot key on it)"
  chk; if find ".agents/skills/$s" -mindepth 2 -name SKILL.md | grep -q .; then
    BAD "skills" "$s: a nested SKILL.md deeper than one level is not discovered"
  fi
done

# --- Codex: .agents/skills only, .codex/agents/*.toml, no auto-delegation ----
for a in $AGENTS; do
  t=".codex/agents/$a.toml"
  chk; [ -f "$t" ] || { BAD "codex" "no subagent router at $t"; continue; }
  for key in name description developer_instructions; do
    chk; has_line "$t" "^$key = " || has_line "$t" "^$key = \"\"\"" || BAD "codex" "$t lacks required key '$key'"
  done
  chk; grep -q "^name = \"$a\"" "$t" || BAD "codex" "$t: name is not \"$a\" — Codex matches on name when spawning"
  chk; grep -q "\.agents/agents/$a\.md" "$t" || BAD "codex" "$t does not route to .agents/agents/$a.md"
done
# Codex never auto-spawns custom subagents; the loop has to ask explicitly.
chk; has_line .agents/skills/ticket-pick/SKILL.md "dispatch each by name" \
  || BAD "codex" "ticket-pick lacks an explicit dispatch instruction — Codex does not auto-delegate to subagents"

# --- Antigravity: .agents/workflows/*.md, 12,000-char cap, subagent: true ----
for s in $PUBLIC; do
  w=".agents/workflows/$s.md"
  chk; [ -f "$w" ] || { BAD "antigravity" "no workflow router at $w (no /$s command)"; continue; }
  chk; [ -n "$(fm "$w" description)" ] || BAD "antigravity" "$w lacks the description: frontmatter that registers the slash command"
  chk; [ "$(size "$w")" -le 12000 ] || BAD "antigravity" "$w is $(size "$w") chars — workflow files are capped at 12,000"
  chk; grep -q "\.agents/skills/$s/SKILL\.md" "$w" || BAD "antigravity" "$w does not route to its skill"
done
for r in .agents/rules/*.md; do
  [ -f "$r" ] || continue
  chk; [ "$(size "$r")" -le 12000 ] || BAD "antigravity" "$r is $(size "$r") chars — rule files are capped at 12,000"
done
for a in $AGENTS; do
  chk; [ "$(fm ".agents/agents/$a.md" subagent)" = "true" ] \
    || BAD "antigravity" ".agents/agents/$a.md lacks 'subagent: true' — invoke_subagent will not see it"
done

# --- Gemini CLI: .gemini/commands/*.toml, .gemini/agents/*.md, context file --
for s in $PUBLIC; do
  c=".gemini/commands/$s.toml"
  chk; [ -f "$c" ] || { BAD "gemini" "no command router at $c (no /$s command)"; continue; }
  chk; has_line "$c" "^prompt = " || BAD "gemini" "$c lacks the required 'prompt' key"
  chk; has_line "$c" "^description = " || BAD "gemini" "$c lacks 'description' (shown in /help)"
  chk; grep -q "{{args}}" "$c" || BAD "gemini" "$c never substitutes {{args}} — user input would be dropped"
  chk; grep -q "\.agents/skills/$s/SKILL\.md" "$c" || BAD "gemini" "$c does not route to its skill"
done
for a in $AGENTS; do
  g=".gemini/agents/$a.md"
  chk; [ -f "$g" ] || { BAD "gemini" "no subagent router at $g"; continue; }
  chk; [ "$(fm "$g" name)" = "$a" ] || BAD "gemini" "$g: frontmatter name != $a"
  chk; [ -n "$(fm "$g" description)" ] || BAD "gemini" "$g lacks description — the planner routes on it"
  chk; grep -q "\.agents/agents/$a\.md" "$g" || BAD "gemini" "$g does not route to the canonical body"
done
chk; [ -f .gemini/settings.json ] || BAD "gemini" ".gemini/settings.json missing — Gemini CLI would read GEMINI.md, not AGENTS.md"
chk; grep -q '"AGENTS.md"' .gemini/settings.json 2>/dev/null \
  || BAD "gemini" ".gemini/settings.json does not name AGENTS.md in context.fileName"
chk; grep -q '"fileName"' .gemini/settings.json 2>/dev/null \
  || BAD "gemini" ".gemini/settings.json has no context.fileName key"

# --- Copilot: .github/agents/*.agent.md -------------------------------------
for a in $AGENTS; do
  c=".github/agents/$a.agent.md"
  chk; [ -f "$c" ] || { BAD "copilot" "no subagent router at $c"; continue; }
  chk; [ "$(fm "$c" name)" = "$a" ] || BAD "copilot" "$c: frontmatter name != $a"
  chk; [ -n "$(fm "$c" description)" ] || BAD "copilot" "$c lacks description"
  chk; [ -n "$(fm "$c" tools)" ] || BAD "copilot" "$c lacks a tools list"
  chk; grep -q "\.agents/agents/$a\.md" "$c" || BAD "copilot" "$c does not route to the canonical body"
done

# --- Claude Code: its own bundle must offer the same surface ----------------
for s in $PUBLIC; do
  case "$s" in
    ticket-*) cmd=".claude/commands/ticket/${s#ticket-}.md" ;;
    *)        cmd=".claude/skills/$s/SKILL.md" ;;
  esac
  chk; [ -f "$cmd" ] || BAD "claude" "$s has no counterpart at $cmd"
done
for a in $AGENTS; do
  chk; [ -f ".claude/agents/$a.md" ] || BAD "claude" "review agent $a missing from .claude/agents/"
done
for s in $SKILLS; do
  case " $PUBLIC " in *" $s "*) continue ;; esac
  chk; [ -f ".claude/skills/$s/SKILL.md" ] || BAD "claude" "internal skill $s missing from .claude/skills/"
done

# --- Routers carry no logic -------------------------------------------------
# The whole design rests on one source of truth. A router that grew a step is a
# second implementation nobody will keep in sync.
for r in .agents/workflows/*.md .gemini/commands/*.toml .gemini/agents/*.md \
         .codex/agents/*.toml .github/agents/*.agent.md; do
  [ -f "$r" ] || continue
  chk; [ "$(size "$r")" -le 2000 ] || BAD "routers" "$r is $(size "$r") chars — routers stay thin; logic belongs in .agents/"
  chk; grep -qE '^#{2,3} (Step|Workflow|Hard rules)' "$r" \
    && BAD "routers" "$r contains workflow structure — it must only name the canonical file" || true
done

# --- Portability invariants -------------------------------------------------
chk; [ -f AGENTS.md ] || BAD "context" "AGENTS.md missing — Codex, Antigravity and Copilot load it as the root context file"
chk; [ -x .agents/scripts/te ] || BAD "bundle" ".agents/scripts/te is not executable (shell returns 126 before te can report it)"
chk; [ -x .claude/scripts/te ] || BAD "bundle" ".claude/scripts/te is not executable"
# `.github/config.yaml|scripts|references` can only ever be the old layout. The
# READMEs legitimately mention `.github/skills` as a path Copilot also accepts,
# so that one is only stale outside prose.
chk; if git grep -qn "\.github/\(config\.yaml\|scripts\|references\)" -- .agents .claude 2>/dev/null; then
  BAD "bundle" "a bundle file still points at the pre-relocation .github/ layout"
fi
chk; if git grep -qn "\.github/skills" -- .agents .claude ':!*README.md' 2>/dev/null; then
  BAD "bundle" "a bundle file still resolves skills from .github/skills"
fi
for def in code-reviewer test-adequacy-reviewer; do
  chk; [ -f ".agents/agents/$def.md" ] || BAD "bundle" "default review.agents entry '$def' has no agent file"
done

if [ "$fail" -ne 0 ]; then
  cat >&2 <<'EOF'

Provider conformance failed. Each check maps to a documented vendor requirement
(docs/platform-support.md § 1). If a router is at fault, fix the canonical file
and re-run scripts/gen-adapters.sh — never hand-edit a generated router.
EOF
  exit 1
fi
echo "test-adapters: ok ($n checks across codex · antigravity · gemini · copilot · claude)"
