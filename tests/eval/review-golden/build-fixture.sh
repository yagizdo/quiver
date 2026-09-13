#!/usr/bin/env bash
# Build the review-golden fixture repo at $1.
#
# Creates a throwaway git repo with two branches:
#   main    -- clean baseline, tests pass
#   feature -- the diff under review (three planted defects, three bait items)
#
# The fixture source lives beside this script as plain files (fixture/main,
# fixture/feature) so it is reviewable in the Quiver repo and never a nested
# git repo. Running this script is the only thing that turns it into one.
set -euo pipefail

dest=${1:-}
if [ -z "$dest" ]; then
  echo "usage: build-fixture.sh <destination-dir>" >&2
  exit 2
fi

here=$(cd "$(dirname "$0")" && pwd)
src="$here/fixture"

mkdir -p "$dest"
dest=$(cd "$dest" && pwd)

git init -q -b main "$dest"
git -C "$dest" config user.name "Quiver Eval"
git -C "$dest" config user.email "eval@example.invalid"
git -C "$dest" config commit.gpgsign false

cp -R "$src/main/." "$dest/"
git -C "$dest" add -A
git -C "$dest" commit -q -m "feat: store baseline"

git -C "$dest" checkout -q -b feature
cp -R "$src/feature/." "$dest/"
git -C "$dest" add -A
git -C "$dest" commit -q -m "feat: add pricing, snapshot export, and paged reports"

git -C "$dest" checkout -q feature
echo "fixture built at $dest (branches: main, feature)"
