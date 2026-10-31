#!/usr/bin/env bash
# Deals the test suites into balanced CI shards. Run by .github/workflows/tests.yml once per
# numbered shard; deal-test.sh beside it runs the same file. Run deal-test.sh after any change here.
#
#   deal.sh <bucket> <buckets> [--skip <dir>]...   that bucket's res:// paths, one per line
#   deal.sh --summary <buckets> [--skip <dir>]...  each bucket's file count and estimated seconds
#
# EVERY .gd under tests/ is dealt, not only the suites. gdUnit4 decides what a suite is (an -a
# naming a helper loads it and runs nothing), so the dealt set is exactly what `-a res://tests`
# scans, and no rule here can disagree with gdUnit4's. A directory holding a .gdignore is skipped,
# as gdUnit4's scanner skips it.
#
# Weights come from times.tsv (refresh.sh writes it); a file it does not list, a new suite or a
# helper, weighs DEFAULT_MS. Largest first, each to the lightest bucket so far, ties to the lower
# bucket. Integer milliseconds and an explicit tiebreak make it deterministic, so every job deals
# the same hand without talking to the others.
#
# Every invocation deals ALL the buckets and refuses unless they partition the whole set: a shard
# that silently stops covering a suite is green, so this is the guard a lost suite gets.
#
# Env, for deal-test.sh only: DEAL_ROOT (the project root), DEAL_TIMES (the table).

set -euo pipefail
export LC_ALL=C

DEFAULT_MS=1000

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=${DEAL_ROOT:-$(cd "$here/../.." && pwd)}
times=${DEAL_TIMES:-$here/times.tsv}

usage() {
  echo "usage: deal.sh <bucket> <buckets> [--skip <dir>]... | deal.sh --summary <buckets> [--skip <dir>]..." >&2
  exit 2
}

[ $# -ge 2 ] || usage
bucket=$1 buckets=$2
shift 2
skips=()
while [ $# -gt 0 ]; do
  [ "$1" = --skip ] && [ $# -ge 2 ] || usage
  skips+=("${2%/}")
  shift 2
done

case "$buckets" in '' | *[!0-9]* | 0) echo "deal.sh: <buckets> must be a positive integer, got '$buckets'" >&2; exit 2 ;; esac
if [ "$bucket" != --summary ]; then
  case "$bucket" in '' | *[!0-9]*) usage ;; esac
  if [ "$bucket" -lt 1 ] || [ "$bucket" -gt "$buckets" ]; then
    echo "deal.sh: bucket $bucket is outside 1..$buckets" >&2
    exit 2
  fi
fi
if [ ! -f "$times" ]; then
  echo "deal.sh: no timing table at $times (tools/ci-shards/refresh.sh writes it)" >&2
  exit 1
fi

cd "$root"
universe=$(find tests -type d -exec test -e '{}/.gdignore' \; -prune -o -type f -name '*.gd' -print \
  | awk -v skips="${skips[*]-}" '
      BEGIN { n = split(skips, s, " ") }
      { for (i = 1; i <= n; i++) if ($0 == s[i] || index($0, s[i] "/") == 1) next
        print "res://" $0 }' \
  | sort)
if [ -z "$universe" ]; then
  echo "deal.sh: found no .gd files under $root/tests" >&2
  exit 1
fi

# bucket <TAB> weight_ms <TAB> path, one line per file.
dealt=$(printf '%s\n' "$universe" \
  | awk -F'\t' -v def="$DEFAULT_MS" '
      FNR == NR { if ($0 !~ /^#/ && NF >= 2) w[$1] = int($2 * 1000 + 0.5); next }
      { print (($1 in w) ? w[$1] : def) "\t" $1 }' "$times" - \
  | sort -t$'\t' -k1,1nr -k2,2 \
  | awk -F'\t' -v n="$buckets" '
      BEGIN { for (i = 1; i <= n; i++) load[i] = 0 }
      { b = 1
        for (i = 2; i <= n; i++) if (load[i] < load[b]) b = i
        load[b] += $1
        print b "\t" $1 "\t" $2 }')

# The partition guard: every file in exactly one bucket, every bucket in range.
if ! cmp -s <(printf '%s\n' "$dealt" | cut -f3 | sort) <(printf '%s\n' "$universe"); then
  echo "deal.sh: the dealt buckets do not cover every file exactly once; refusing" >&2
  exit 1
fi
if printf '%s\n' "$dealt" | awk -F'\t' -v n="$buckets" '$1 < 1 || $1 > n { bad = 1 } END { exit !bad }'; then
  echo "deal.sh: a file was dealt outside buckets 1..$buckets; refusing" >&2
  exit 1
fi

if [ "$bucket" = --summary ]; then
  printf '%s\n' "$dealt" | awk -F'\t' -v n="$buckets" '
    { files[$1]++; ms[$1] += $2 }
    END { for (i = 1; i <= n; i++) printf "bucket %d/%d: %d files, ~%.0fs\n", i, n, files[i], ms[i] / 1000 }'
else
  printf '%s\n' "$dealt" | awk -F'\t' -v k="$bucket" '$1 == k { print $3 }' | sort
fi
