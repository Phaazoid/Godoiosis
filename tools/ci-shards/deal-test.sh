#!/usr/bin/env bash
# Checks deal.sh: on the real tree, that separate invocations (one per CI job) together cover every
# .gd under tests/ exactly once and agree with each other; on a throwaway tree, that the dealing,
# the default weight, --skip, .gdignore and the argument refusals do what deal.sh says. Touches
# nothing in this repository.
#
#   bash tools/ci-shards/deal-test.sh
#
# DEAL_SCRIPT=<path> runs the cases against another script, to prove a case can go red.
# Exits non-zero if any case fails.

set -uo pipefail
export LC_ALL=C

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/../.." && pwd)
deal=${DEAL_SCRIPT:-$here/deal.sh}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

failures=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

# -- The real tree: the property CI leans on. Each job runs deal.sh on its own, so the union of
# separate invocations is what is checked, against a listing deal.sh had no part in.
(cd "$repo" && find tests -type f -name '*.gd' | grep -v '^tests/export/' | sed 's|^|res://|' | sort) > "$tmp/expected"
for n in 1 2 3 4 5 6 7; do
  : > "$tmp/union"
  for ((k = 1; k <= n; k++)); do
    bash "$deal" "$k" "$n" --skip tests/export >> "$tmp/union" || { fail "real tree: deal.sh $k $n exited non-zero"; continue 2; }
  done
  if [ -n "$(sort "$tmp/union" | uniq -d)" ]; then
    fail "real tree, $n buckets: a file is dealt twice"
  elif ! cmp -s <(sort "$tmp/union") "$tmp/expected"; then
    fail "real tree, $n buckets: the buckets do not cover every .gd under tests/"
  else
    pass "real tree, $n buckets: every file in exactly one bucket"
  fi
done
if cmp -s <(bash "$deal" 3 5 --skip tests/export) <(bash "$deal" 3 5 --skip tests/export); then
  pass "real tree: two invocations deal the same hand"
else
  fail "real tree: two invocations dealt different hands"
fi

# -- A throwaway tree with a known answer. Largest first, each to the lighter bucket:
#    a 5 -> 1 (5) | b 4 -> 2 (4) | c 3 -> 2 (7) | d 3 -> 1 (8) | e 2 -> 2 (9) | f (unlisted, 1) -> 1 (9)
# c and d tie on weight and go in path order; f proves the default weight.
fake=$tmp/fake
mkdir -p "$fake/tests/one" "$fake/tests/two" "$fake/tests/export" "$fake/tests/ignored"
for f in one/test_a one/test_b two/test_c two/test_d two/test_e two/test_f export/test_x ignored/test_y; do
  : > "$fake/tests/$f.gd"
done
: > "$fake/tests/ignored/.gdignore"
printf '%s\n' '# a comment line' \
  "res://tests/one/test_a.gd	5" "res://tests/one/test_b.gd	4" "res://tests/two/test_c.gd	3" \
  "res://tests/two/test_d.gd	3" "res://tests/two/test_e.gd	2" "res://tests/export/test_x.gd	50" > "$fake/times.tsv"
fake_deal() { DEAL_ROOT=$fake DEAL_TIMES=$fake/times.tsv bash "$deal" "$@"; }

expect() {
  local name=$1 want=$2; shift 2
  local got
  got=$(fake_deal "$@" 2>/dev/null | tr '\n' ' ')
  if [ "$got" = "$want" ]; then pass "$name"; else fail "$name: wanted '$want', got '$got'"; fi
}
expect "known hand, bucket 1" "res://tests/one/test_a.gd res://tests/two/test_d.gd res://tests/two/test_f.gd " 1 2 --skip tests/export
expect "known hand, bucket 2" "res://tests/one/test_b.gd res://tests/two/test_c.gd res://tests/two/test_e.gd " 2 2 --skip tests/export
expect "summary" "bucket 1/2: 3 files, ~9s bucket 2/2: 3 files, ~9s " --summary 2 --skip tests/export
expect "without --skip, the skipped folder is dealt" "res://tests/export/test_x.gd " 1 2

refuses() {
  local name=$1; shift
  if fake_deal "$@" > /dev/null 2>&1; then fail "$name: deal.sh accepted it"; else pass "$name"; fi
}
refuses "refuses bucket 0" 0 2
refuses "refuses a bucket past the count" 3 2
refuses "refuses zero buckets" 1 0
refuses "refuses a stray argument" 1 2 --nope
if DEAL_ROOT=$fake DEAL_TIMES=$fake/missing.tsv bash "$deal" 1 2 > /dev/null 2>&1; then
  fail "refuses a missing table: deal.sh accepted it"
else
  pass "refuses a missing table"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures case(s) failed"
  exit 1
fi
echo "all cases passed"
