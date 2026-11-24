#!/bin/zsh
# Build MiniDeck and publish it as a GitHub release.
# Usage: ./release.sh 0.24 "What changed"
set -euo pipefail
cd "${0:A:h}"
VERSION=${1:?usage: ./release.sh <version> "<what changed>"}
NOTES=${2:-}
TAG=v$VERSION

[[ $VERSION =~ '^[0-9]+(\.[0-9]+)+$' ]] || { echo "Version should look like 0.24"; exit 1; }
[[ -z $(git status --porcelain) ]] || { echo "Commit or stash your changes first"; exit 1; }
[[ $(git branch --show-current) == main ]] || { echo "Release from main"; exit 1; }
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "$TAG already exists"; exit 1; }

echo $VERSION > VERSION
./build.sh
ZIP=dist/MiniDeck-$VERSION.zip
cp dist/MiniDeck.zip $ZIP

git add VERSION
git diff --cached --quiet || git commit -q -m "Release $VERSION"
git tag -a $TAG -m "MiniDeck $VERSION"
git push -q origin main $TAG

gh release create $TAG $ZIP --title "MiniDeck $VERSION" --notes "$NOTES

### Install
1. Download **MiniDeck-$VERSION.zip** below and unzip it.
2. Drag **MiniDeck.app** into **Applications** and open it from there.
3. The app isn't notarized by Apple, so the first time macOS says it can't verify the developer:
   right-click the app → **Open**, or go to **System Settings → Privacy & Security → Open Anyway**.
4. Allow MiniDeck to control **Music** when asked.

Requires macOS 14 or later (Liquid Glass needs macOS 26). Universal: Apple Silicon and Intel."
echo "Released $TAG"
