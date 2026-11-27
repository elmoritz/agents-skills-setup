#!/usr/bin/env bash
# Offline control-flow test for the /ticket:auto Workflow script
# (.claude/references/auto-workflow/ticket-auto.js): runs it against scripted
# agents — no model, no tokens — and asserts every scenario's outcome. Needs node.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
command -v node >/dev/null || { echo "test-auto-workflow: node not found"; exit 1; }
exec node tests/auto-workflow/harness.mjs .claude/references/auto-workflow/ticket-auto.js
