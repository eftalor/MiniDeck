#!/bin/zsh
# Publish a new MiniDeck version. GitHub Actions builds it and creates the release.
# Usage: ./release.sh 0.25 "What changed"
set -euo pipefail
cd "${0:A:h}"
VERSION=${1:?usage: ./release.sh <version> "<what changed>"}
NOTES=${2:-MiniDeck $VERSION}
TAG=v$VERSION

[[ $VERSION =~ '^[0-9]+(\.[0-9]+)+$' ]] || { echo "Version should look like 0.25"; exit 1; }
[[ -z $(git status --porcelain) ]] || { echo "Commit or stash your changes first"; exit 1; }
[[ $(git branch --show-current) == main ]] || { echo "Release from main"; exit 1; }
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "$TAG already exists"; exit 1; }

echo $VERSION > VERSION
git add VERSION
git diff --cached --quiet || git commit -q -m "Release $VERSION"
git tag -a $TAG -m "$NOTES"     # the tag message becomes the release notes
git push -q origin main $TAG
echo "Pushed $TAG; GitHub is building it."

# Follow the build (Ctrl-C is fine; it keeps going on GitHub).
sleep 8
RUN=$(gh run list --workflow build.yml --branch $TAG --limit 1 --json databaseId -q '.[0].databaseId' || true)
if [[ -n $RUN ]]; then
  gh run watch $RUN --exit-status && gh release view $TAG --json url -q .url
else
  echo "Watch it at: $(gh repo view --json url -q .url)/actions"
fi
