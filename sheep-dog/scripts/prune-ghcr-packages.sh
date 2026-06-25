#!/usr/bin/env bash
# Prune GitHub Packages (ghcr.io) container versions for farhan5248, keeping only
# the newest version of each package. Intended to run AFTER the AWS teardown +
# smoke test, so nothing lingers in GitHub Packages (see issue #522).
#
# Usage:
#   scripts/prune-ghcr-packages.sh            # delete all but newest per package
#   scripts/prune-ghcr-packages.sh --dry-run  # show what would be deleted
#   scripts/prune-ghcr-packages.sh --keep 0   # delete ALL versions (full teardown)
#
# Requires: gh CLI authed with a token carrying the `delete:packages` scope.

set -euo pipefail

OWNER="farhan5248"
KEEP=1
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --keep) KEEP="$2"; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

echo "Pruning ghcr.io container packages for $OWNER (keep newest $KEEP per package, dry-run=$DRY_RUN)"
echo

# All container packages owned by the user.
PACKAGES=$(gh api "/user/packages?package_type=container" --paginate --jq '.[].name')

for pkg in $PACKAGES; do
  # Versions come back newest-first; drop the first $KEEP, delete the rest.
  ids=$(gh api "/user/packages/container/$pkg/versions" --paginate \
        --jq ".[$KEEP:] | .[].id")
  if [ -z "$ids" ]; then
    echo "=== $pkg: nothing to delete ==="
    continue
  fi
  count=$(echo "$ids" | wc -w | tr -d ' ')
  echo "=== $pkg: deleting $count version(s) ==="
  for id in $ids; do
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "  [dry-run] would delete version $id"
    else
      gh api --method DELETE "/user/packages/container/$pkg/versions/$id" \
        && echo "  deleted version $id"
    fi
  done
done

echo
echo "Done."
