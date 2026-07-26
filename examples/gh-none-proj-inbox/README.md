# example: gh-none-proj-inbox

GitHub-backed flavor. Only `.claude/config.yaml` is local — issues, workflow labels, and the Projects v2 board live on
GitHub, created by /ticket:init's side effects (and by te's write path). The
read path (te read/list/deps/milestone) is exercised offline against recorded
fixtures in tests/fixtures/gh/, and live against a throwaway repo by
scripts/live-gh-check.sh.
