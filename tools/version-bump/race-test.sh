#!/usr/bin/env bash
# Reproduces the version-bump push race (#1398) on demand. Each case builds, in a temp dir, a
# bare "remote" at version 0.1.0, a runner clone (the workflow's checkout) and a racer clone (a
# merge landing), then runs bump.sh in the runner while a git hook in the runner lands the
# racer's commit at the moment a real merge did. Touches nothing in this repository.
#
#   bash tools/version-bump/race-test.sh
#
# BUMP_SCRIPT=<path> runs the cases against another script, to prove a case can go red.
# Exits non-zero if any case fails.

set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bump=${BUMP_SCRIPT:-$here/bump.sh}
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

# Isolate from the caller's git config: hooksPath, signing, autocrlf, default branch.
: > "$root/gitconfig"
export GIT_CONFIG_GLOBAL=$root/gitconfig GIT_CONFIG_NOSYSTEM=1
export BUMP_BACKOFF_SECONDS=0

# race.sh <case dir> <merge|bump|refuse> <once|always>: what a runner hook does.
cat > "$root/race.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# A hook inherits the runner's repository; the racer is another one.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_OBJECT_DIRECTORY
dir=$1 mode=$2 times=$3
if [ "$mode" = refuse ]; then
  exit 1
fi
if [ "$times" = once ] && [ -e "$dir/raced" ]; then
  exit 0
fi
echo x >> "$dir/raced"
cd "$dir/racer"
git fetch --quiet origin main
git reset --quiet --hard origin/main
if [ "$mode" = bump ]; then
  current=$(sed -n 's/^config\/version="\(.*\)"$/\1/p' project.godot)
  IFS=. read -r major minor patch <<< "$current"
  sed -i "s|^config/version=\".*\"|config/version=\"$major.$minor.$((patch + 1))\"|" project.godot
  git commit --quiet -am "racing bump"
else
  echo merged >> merged.txt
  git add merged.txt
  git commit --quiet -m "racing merge"
fi
git push --quiet origin HEAD:main
EOF

failures=0
dir='' status=0 version='' attempts=0 racers=0 tip='' body='' case_ok=1

# run_case <name> <labels> <hook: none|post-commit|pre-push> <race mode> <once|always> <max attempts>
run_case() {
  local name=$1 labels=$2 hook=$3 mode=$4 times=$5 max=$6
  dir=$root/$name
  case_ok=1
  mkdir -p "$dir"
  git init --quiet --bare --initial-branch=main "$dir/remote.git"
  git init --quiet --initial-branch=main "$dir/racer"
  (
    cd "$dir/racer"
    git config user.name racer
    git config user.email racer@example.invalid
    printf '[application]\n\nconfig/version="0.1.0"\n' > project.godot
    git add project.godot
    git commit --quiet -m seed
    git remote add origin "$dir/remote.git"
    git push --quiet origin main
  )
  git clone --quiet "$dir/remote.git" "$dir/runner"
  if [ "$hook" != none ]; then
    printf '#!/usr/bin/env bash\nexec bash "%s" "%s" %s %s\n' "$root/race.sh" "$dir" "$mode" "$times" \
      > "$dir/runner/.git/hooks/$hook"
    chmod +x "$dir/runner/.git/hooks/$hook"
  fi

  set +e
  (cd "$dir/runner" && LABELS=$labels PR_NUMBER=42 BUMP_MAX_ATTEMPTS=$max bash "$bump") \
    > "$dir/out.log" 2>&1
  status=$?
  set -e

  local remote=(git --git-dir="$dir/remote.git")
  version=$("${remote[@]}" show main:project.godot | sed -n 's/^config\/version="\(.*\)"$/\1/p')
  attempts=$(grep -c '^attempt ' "$dir/out.log" || true)
  racers=$("${remote[@]}" log --format=%s main | grep -c '^racing ' || true)
  tip=$("${remote[@]}" log -1 --format=%s main)
  body=$("${remote[@]}" log -1 --format=%b main)
}

expect() { # <what> <actual> <wanted>
  if [ "$2" != "$3" ]; then
    echo "    $1: got '$2', wanted '$3'"
    case_ok=0
  fi
}

expect_log() { # <text bump.sh must have printed>
  if ! grep -qF -- "$1" "$dir/out.log"; then
    echo "    output lacks: $1"
    case_ok=0
  fi
}

report() { # <description>
  local refusal
  refusal=$(grep -m1 -E '^ ! \[' "$dir/out.log" || true)
  if [ "$case_ok" = 1 ]; then
    echo "PASS  $1${refusal:+   (git:$refusal)}"
  else
    echo "FAIL  $1"
    sed 's/^/    | /' "$dir/out.log"
    failures=$((failures + 1))
  fi
}

run_case no-race '[]' none - - 8
expect exit "$status" 0
expect version "$version" 0.1.1
expect attempts "$attempts" 1
expect tip "$tip" "Version 0.1.1"
expect body "$body" "Bumped on merge of #42 (fix)."
report "no race, unlabelled: the last digit"

run_case feature '["type/bug","type/feature"]' none - - 8
expect exit "$status" 0
expect version "$version" 0.2.0
expect body "$body" "Bumped on merge of #42 (feature)."
report "no race, type/feature: the middle digit"

run_case merge-before-push '[]' post-commit merge once 8
expect exit "$status" 0
expect version "$version" 0.1.1
expect attempts "$attempts" 2
expect "racing commits on main" "$racers" 1
expect tip "$tip" "Version 0.1.1"
expect_log "::notice::lost the race to main 1 time(s); pushed 0.1.1 on attempt 2"
report "a merge lands between the fetch and the push (#1385, #1390)"

run_case merge-during-push '[]' pre-push merge once 8
expect exit "$status" 0
expect version "$version" 0.1.1
expect attempts "$attempts" 2
expect "racing commits on main" "$racers" 1
expect tip "$tip" "Version 0.1.1"
report "a merge lands during the push (#1341, #1392)"

run_case rival-bump '[]' post-commit bump once 8
expect exit "$status" 0
expect version "$version" 0.1.2
expect attempts "$attempts" 2
expect "racing commits on main" "$racers" 1
expect tip "$tip" "Version 0.1.2"
report "the commit that lands first is another bump: recompute, never rebase"

run_case refused '[]' pre-push refuse always 8
expect exit "$status" 1
expect version "$version" 0.1.0
expect attempts "$attempts" 1
expect_log "push refused but main has not moved"
report "a refusal with main unmoved is not a race and is not retried"

run_case always-loses '[]' post-commit merge always 3
expect exit "$status" 1
expect version "$version" 0.1.0
expect attempts "$attempts" 3
expect "racing commits on main" "$racers" 3
expect_log "re-run this job to apply PR #42's bump"
report "every attempt loses: fails loud after BUMP_MAX_ATTEMPTS"

if [ "$failures" -gt 0 ]; then
  echo "$failures case(s) failed"
  exit 1
fi
echo "all cases passed"
