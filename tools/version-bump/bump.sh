#!/usr/bin/env bash
# Bumps application/config/version on main for one merged PR. Run by
# .github/workflows/version-bump.yml from a checkout of main; race-test.sh beside it runs the
# same file against a throwaway remote. Run race-test.sh after any change here.
#
# Env: LABELS     quoted JSON array of the merged PR's label names
#      PR_NUMBER  the merged PR
#      BUMP_MAX_ATTEMPTS, BUMP_BACKOFF_SECONDS  overrides for race-test.sh only
#
# The number is main's own at push time plus one, never the PR's, so every attempt re-reads
# main and recomputes. An unforced push is the compare-and-swap: it lands only if main has not
# moved since the fetch, so two runs can never push the same number (#1398).

# Wrapped so bash parses the whole file before the reset below can rewrite it.
main() {
  set -euo pipefail

  local max_attempts=${BUMP_MAX_ATTEMPTS:-8}
  local backoff=${BUMP_BACKOFF_SECONDS:-2}

  local kind=fix
  if printf '%s' "$LABELS" | grep -q '"type/feature"'; then
    kind=feature
  fi

  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

  local attempt base current major minor patch next
  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    git fetch --quiet origin main
    git reset --quiet --hard origin/main
    base=$(git rev-parse HEAD)

    current=$(sed -n 's/^config\/version="\(.*\)"$/\1/p' project.godot)
    if [ -z "$current" ]; then
      echo "::error::could not read application/config/version from project.godot"
      exit 1
    fi
    IFS=. read -r major minor patch <<< "$current"
    if [ "$kind" = feature ]; then
      minor=$((minor + 1))
      patch=0
    else
      patch=$((patch + 1))
    fi
    next="$major.$minor.$patch"
    echo "attempt $attempt: $current -> $next ($kind, PR #$PR_NUMBER)"

    sed -i "s|^config/version=\".*\"|config/version=\"$next\"|" project.godot
    if git diff --quiet -- project.godot; then
      echo "::error::version unchanged; refusing to push an empty commit"
      exit 1
    fi
    git add project.godot
    # -F -, never -m with interpolated PR text.
    printf 'Version %s\n\nBumped on merge of #%s (%s).\n' "$next" "$PR_NUMBER" "$kind" \
      | git commit --quiet -F -

    if git push origin HEAD:main; then
      if [ "$attempt" -gt 1 ]; then
        echo "::notice::lost the race to main $((attempt - 1)) time(s); pushed $next on attempt $attempt"
      fi
      return 0
    fi

    # Only a main that moved is a race worth another attempt.
    git fetch --quiet origin main
    if [ "$(git rev-parse origin/main)" = "$base" ]; then
      echo "::error::push refused but main has not moved, so this is not a race; not retrying"
      exit 1
    fi
    echo "main moved under attempt $attempt; recomputing"
    sleep $((attempt * backoff + RANDOM % (backoff + 1)))
  done

  echo "::error::lost the race to main $max_attempts times; re-run this job to apply PR #$PR_NUMBER's bump"
  exit 1
}

main "$@"
