#!/bin/bash
# One unattended playtest run, in an ISOLATED worktree.
#     IOSIS_PLAYTEST_WT=... IOSIS_PLAYTEST_PROJECT=... tools/playtest/run.sh <n>
#
# Read docs/playtest-experiments.md before using this. The traps it records cost real runs.
set -u
# --- config (override by env) -----------------------------------------------------------------
# WT   the worktree the session plays in. NOT your working checkout: an unattended agent runs with
#      permissions auto-approved, so the blast radius should be a tree you can throw away.
# PROJ the agy project id pinning the session to WT. See docs/playtest-experiments.md -- agy binds
#      to a PROJECT, not to cwd, and getting this wrong silently plays in the wrong repo.
WT="${IOSIS_PLAYTEST_WT:?set IOSIS_PLAYTEST_WT to the playtest worktree}"
PROJ="${IOSIS_PLAYTEST_PROJECT:?set IOSIS_PLAYTEST_PROJECT to the agy project id}"
HERE="${IOSIS_PLAYTEST_OUT:-$HOME/iosis-playtest}"
ARM="${IOSIS_PLAYTEST_ARM:-C}"
# agy binds to a PROJECT, not to cwd. Run 1 proved that the hard way: launched from the worktree,
# it played in the main checkout instead and this script archived zero frames. The project below
# pins folderUri to the worktree; ~/.gemini/config/projects/<id>.json is its definition.
N="$1"
OUT="$HERE/runs/$ARM-$N"
[ -d "$OUT" ] && { echo "$ARM-$N already exists"; exit 1; }

cd "$WT" || exit 1
# The worktree is the blast radius. A session that ignores "do not modify files" damages a
# throwaway checkout, never the working tree -- and this asserts it started clean so a dirty tree
# afterwards is attributable to THIS run.
git checkout -q . 2>/dev/null; git clean -qfd 2>/dev/null
rm -rf playrun/frames/* playrun/state.txt playrun/command.json 2>/dev/null
pkill -f "play_bridge" 2>/dev/null; sleep 1

echo "=== $ARM-$N starting $(date -u +%FT%TZ) @ $(git rev-parse --short HEAD)"
START=$(date +%s)
# No outer `timeout`: macOS has no such binary (that cost run 1, harmlessly -- rc=127, nothing
# launched, no budget spent). agy enforces its own bound with --print-timeout.
agy -p "$(cat "$(dirname "$0")/prompt.md")" --project "$PROJ" \
  --dangerously-skip-permissions --print-timeout 20m > "$HERE/.$ARM$N.stdout" 2>&1
RC=$?
END=$(date +%s)
pkill -f "play_bridge" 2>/dev/null

mkdir -p "$OUT"
cp -R playrun/frames "$OUT/" 2>/dev/null
# The isolation check, and it FAILS LOUD rather than archiving nothing quietly: zero frames here
# means the session played somewhere else, which is the whole thing the project pin prevents.
if [ "$(ls "$OUT/frames" 2>/dev/null | wc -l | tr -d ' ')" = "0" ]; then
  echo "!! NO FRAMES in the worktree -- the session did not play here. Check the project pin."
  echo "   look for frames elsewhere -- a session that ignored the pin played in another checkout."
fi
cp "$HERE/.$ARM$N.stdout" "$OUT/agent-stdout.txt" 2>/dev/null
DIRTY=$(git status --porcelain | head -20)
{ echo "arm=$ARM"; echo "run=$N"; echo "commit=$(git rev-parse --short HEAD)";
  echo "seconds=$((END-START))"; echo "agy_rc=$RC";
  echo "frame_dirs=$(ls "$OUT/frames" 2>/dev/null | wc -l | tr -d ' ')";
  echo "worktree_dirty=$([ -z "$DIRTY" ] && echo no || echo YES)"; } > "$OUT/manifest.txt"
[ -n "$DIRTY" ] && { echo "$DIRTY" > "$OUT/worktree-changes.txt"; echo "!! the session modified files (recorded, then reverted)"; }
git checkout -q . 2>/dev/null; git clean -qfd 2>/dev/null

DB=$(ls -t ~/.gemini/antigravity-cli/conversations/*.db 2>/dev/null | head -1)
if [ -n "$DB" ] && [ "$(stat -f %m "$DB")" -gt "$START" ]; then
  cp "$DB" "$OUT/conversation.db"
  "$(dirname "$0")/extract-transcript.sh" "$DB" "$OUT/transcript.txt" >/dev/null 2>&1
  echo "transcript=$(basename "$DB")" >> "$OUT/manifest.txt"
fi
echo "=== $ARM-$N done in $((END-START))s (rc=$RC)"; cat "$OUT/manifest.txt" | sed 's/^/  /'
