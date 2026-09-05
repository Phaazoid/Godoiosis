#!/bin/bash
# ./analyze.sh              -- every saved run, then the arm comparison
# ./analyze.sh runs/A-1     -- one run
#
# Metrics fixed BEFORE either arm ran (see below). A run may hold SEVERAL frame dirs, because a
# session that restarts the bridge starts a new one -- Gemini restarted 23 times in one baseline
# session -- so a run is aggregated across all of them rather than being its first dir.
row() {
  local D="$1" L="$2"
  # ONLY the frame log. `save` archives transcript.txt beside it, and counting that as output
  # inflated BYTES by 4x on the first run analysed -- the metric would have been measuring my own
  # archiving rather than what the bridge sent.
  local F=$(find "$D" -path '*frames*' -name '*.txt' 2>/dev/null)
  [ -z "$F" ] && return
  local tot=$(grep -h "^@@" $F 2>/dev/null | wc -l | tr -d ' ')
  local bad=$(grep -h "^@@" $F 2>/dev/null | grep -c "ok=0")
  local all=$(cat $F 2>/dev/null | wc -c | tr -d ' ')
  local turns=$(grep -lh "Turn -> PLAYER" $F 2>/dev/null | wc -l | tr -d ' ')
  # Counted from the CONTENT, not the filename. Batching broke the filename version silently: a
  # batch is named for its LAST command, so an `overview` inside one is invisible to a glob -- and
  # this is the pre-registered guard, so a blind guard is worse than none.
  local ovs=$(cat $F 2>/dev/null | grep -cE "^\[[0-9]+\] overview|cmd=overview")
  local exs=$(cat $F 2>/dev/null | grep -cE "^\[[0-9]+\] execute|cmd=execute")
  local aff=$(cat $F 2>/dev/null | grep -cE "^\[[0-9]+\] legal_(moves|targets)|cmd=legal_")
  # python3 invocations, the #666 metric: an agent that must run arbitrary code cannot be given a
  # narrow allowlist, and the count tracks round trips rather than taste.
  local py="-"
  [ -f "$D/conversation.db" ] && py=$(sqlite3 "$D/conversation.db" "select hex(step_payload) from steps where step_type=15;" 2>/dev/null | xxd -r -p 2>/dev/null | strings -n 8 | grep -oE '"CommandLine":"[^"]{0,60}' | grep -c python)
  printf '%-14s %6s %7s%% %6s %9s %8s %9s %7s %6s\n' "$L" "$tot" \
    "$([ "$tot" -gt 0 ] && echo $((bad*100/tot)) || echo 0)" "$turns" "$all" \
    "$([ "$turns" -gt 0 ] && echo $((all/turns)) || echo -)" \
    "$([ "$exs" -gt 0 ] && echo "scale=2;$ovs/$exs" | bc || echo -)" "$aff" "$py"
}
hdr() { printf '%-14s %6s %8s %6s %9s %8s %9s %7s %6s\n' RUN FRAMES REJECT TURNS BYTES B/TURN OV/EXEC AFFORD PY; }
if [ -n "$1" ]; then hdr; row "$1" "$(basename $1)"; exit 0; fi
hdr
for d in "${IOSIS_PLAYTEST_OUT:-$HOME/iosis-playtest}"/runs/*-*; do [ -d "$d" ] && row "$d" "$(basename $d)"; done
echo
echo "PRIMARY is REJECT (baseline 30-54%).  GUARD is OV/EXEC: baseline 0.67 -- if arm B"
echo "approaches or exceeds that, the redraw MOVED rather than went away and #613 should be"
echo "reconsidered.  AFFORD counts arm B's discovery of the new queries; 0 means the feature"
echo "shipped inert however good it is."
