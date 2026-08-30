#!/bin/bash
# Send one command (or a batch) to the headless play bridge and print the reply.
#
#     play/send.sh overview
#     play/send.sh move '{"unit":"A","x":22,"y":7}'
#     play/send.sh --batch '[{"cmd":"legal_moves","args":{"unit":"A"}},{"cmd":"preview"}]'
#
# WHY THIS SHIPS (#666). The bridge is a write-then-poll protocol: write command.json, then wait
# for state.txt to show your id. That is fine a dozen times and unbearable seventy times, so every
# playtest driver so far wrote its own poller in Python and ran it in a loop -- 69 of 72 shell
# calls in one logged run, 54 of 61 in another. The one run that batched aggressively needed three
# shell commands total and no Python at all.
#
# An agent that must run arbitrary python3 cannot be given a narrow permission allowlist, so an
# unattended playtest needs blanket approval -- which removes the guard that keeps a session that
# is supposed to be PLAYING the game from editing it. The permission problem and the interface
# problem are the same problem, and this is the interface half: with this script the whole
# allowlist is two entries, launching the bridge and running this.
#
# Prefer --batch. A turn is usually one batch, and round-trip count is what drove the scripting.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$ROOT/playrun"
CMD="$RUN/command.json"
STATE="$RUN/state.txt"
TIMEOUT_S="${SEND_TIMEOUT:-30}"

[ -d "$RUN" ] || { echo "no $RUN -- is the bridge running?" >&2; exit 1; }

# The next id, read from whatever the bridge last answered. Ids must increase or the bridge
# ignores the command as stale.
last=$(grep -oE 'id=[0-9]+' "$STATE" 2>/dev/null | tail -1 | cut -d= -f2)
id=$(( ${last:-0} + 1 ))

if [ "${1:-}" = "--batch" ]; then
  [ $# -ge 2 ] || { echo "usage: send.sh --batch '<json array of {cmd,args}>'" >&2; exit 1; }
  printf '{"id":%d,"cmds":%s}' "$id" "$2" > "$CMD"
else
  [ $# -ge 1 ] || { echo "usage: send.sh <cmd> ['<json args>']  |  send.sh --batch '<json array>'" >&2; exit 1; }
  args="${2:-{\}}"
  printf '{"id":%d,"cmd":"%s","args":%s}' "$id" "$1" "$args" > "$CMD"
fi

# Poll for OUR id specifically. Matching on "id=$id " with the trailing space is what stops id=1
# matching the reply to id=12.
deadline=$(( $(date +%s) + TIMEOUT_S ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if grep -q "id=$id " "$STATE" 2>/dev/null; then
    cat "$STATE"
    exit 0
  fi
  sleep 0.15
done
echo "TIMEOUT after ${TIMEOUT_S}s waiting for id=$id (bridge died? check its stdout)" >&2
exit 1
