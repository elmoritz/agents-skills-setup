#!/usr/bin/env bash
# gen-examples.sh — regenerate examples/<flavor>/ for every valid config flavor
# via te-scaffold.sh. The examples are committed (browsable reference + cd-in
# sandboxes); this script recreates them, like a golden --update. Config-invalid
# combinations are excluded by construction (projects-on requires github; native
# requires github; trackers requires filesystem).
#
# Flavor matrix (18):
#   filesystem × milestones{auto→trackers, labels, none} × inbox{y,n}            = 6
#   github     × milestones{auto→native,   labels, none} × inbox{y,n} × proj{on,off} = 12
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
SCAFFOLD=scripts/te-scaffold.sh
EX=examples
rm -rf "$EX"; mkdir -p "$EX"

# name : backend : milestones : inbox-flag : projects-flag : seed-flag
FLAVORS="
fs-trackers            : fs : auto   :         :            : --seed
fs-trackers-inbox      : fs : auto   : --inbox :            : --seed
fs-labels              : fs : labels :         :            : --seed
fs-labels-inbox        : fs : labels : --inbox :            : --seed
fs-none                : fs : none   :         :            : --seed
fs-none-inbox          : fs : none   : --inbox :            : --seed
gh-native              : gh : auto   :         :            :
gh-native-inbox        : gh : auto   : --inbox :            :
gh-native-proj         : gh : auto   :         : --projects :
gh-native-proj-inbox   : gh : auto   : --inbox : --projects :
gh-labels              : gh : labels :         :            :
gh-labels-inbox        : gh : labels : --inbox :            :
gh-labels-proj         : gh : labels :         : --projects :
gh-labels-proj-inbox   : gh : labels : --inbox : --projects :
gh-none                : gh : none   :         :            :
gh-none-inbox          : gh : none   : --inbox :            :
gh-none-proj           : gh : none   :         : --projects :
gh-none-proj-inbox     : gh : none   : --inbox : --projects :
"

# Special flavors beyond the strict matrix — cover config shapes /ticket:init
# emits that the matrix dimensions don't reach: a native issue-type map, a
# research-agents block, and a user-owned (not org) Project.
SPECIALS="
gh-native-typemap      : gh : auto   :         :            :       : --type-map
fs-trackers-research   : fs : auto   :         :            : --seed : --research perf-expert,language-expert
gh-native-proj-user    : gh : auto   :         : --projects :       : --owner-type user
"

trim() { printf '%s' "$1" | sed -e 's/^ *//' -e 's/ *$//'; }

printf '%s\n%s\n' "$FLAVORS" "$SPECIALS" | while IFS=: read -r name be ms ib pj seed extra; do
  name=$(trim "$name"); [ -n "$name" ] || continue
  be=$(trim "$be"); ms=$(trim "$ms"); ib=$(trim "$ib"); pj=$(trim "$pj"); seed=$(trim "$seed"); extra=$(trim "$extra")
  "$SCAFFOLD" --out "$EX/$name" --backend "$be" --milestones "$ms" $ib $pj $seed $extra >/dev/null
  # github examples carry no local tickets (issues live on GitHub) — a README
  # explains what init would have created remotely.
  if [ "$be" = gh ]; then
    extras="issues and workflow labels"
    [ "$pj" = --projects ] && extras="issues, workflow labels, and the Projects v2 board"
    cat > "$EX/$name/README.md" <<EOF
# example: $name

GitHub-backed flavor. Only \`.claude/config.yaml\` is local — $extras live on
GitHub, created by /ticket:init's side effects (and by te's write path). The
read path (te read/list/deps/milestone) is exercised offline against recorded
fixtures in tests/fixtures/gh/, and live against a throwaway repo by
scripts/live-gh-check.sh.
EOF
  fi
  echo "  $name"
done

cp scripts/examples-README.md "$EX/README.md"
echo "regenerated $EX/ ($(ls -d "$EX"/*/ | wc -l | tr -d ' ') flavors)"
