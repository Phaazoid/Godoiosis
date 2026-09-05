#!/bin/bash
# extract-transcript.sh <conversation.db> <out.txt>
# agy stores a session as protobuf blobs in SQLite. Not fully decodable without the schema, but the
# parts that matter for a playtest post-mortem come out as readable strings: the prompt it was
# given, every tool call with its JSON arguments, and the model's own running status summaries --
# which is where "what it was TRYING to do" lives, the half the frame log cannot show.
DB="$1"; OUT="$2"
[ -f "$DB" ] || { echo "no such db: $DB"; exit 1; }
{
  echo "=== transcript extracted from $(basename "$DB") on $(date -u +%FT%TZ)"
  echo "=== steps: $(sqlite3 "$DB" 'select count(*) from steps;')"
  echo
  sqlite3 "$DB" "select idx, step_type, hex(step_payload) from steps order by idx;" \
  | while IFS='|' read -r idx type hex; do
      text=$(echo "$hex" | xxd -r -p 2>/dev/null | strings -n 20 \
             | grep -vE '^\$|^"\$|^bot-|sessionID|^[A-Za-z0-9+/]{30,}=*$' | head -40)
      [ -z "$text" ] && continue
      echo "--- step $idx (type $type)"
      echo "$text"
      echo
    done
} > "$OUT"
echo "wrote $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"
