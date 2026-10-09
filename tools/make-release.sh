#!/bin/sh
# Makes a release of the Macintosh Backup Utility (Stage 6), from the
# committed source, as the other MacMusic utilities' releases are, into
#   ~/MacPlusProjects/releases/Macintosh-Backup-Utility-<version>/
# holding:
#   Macintosh-Backup-Utility-<version>.zip   the app (unzip, drag to Applications)
#   RELEASE-NOTES.md, SHA256SUMS
#   source/MacintoshBackup.bundle            the whole repository (git bundle, with tags)
#   checks/tests.txt, checks/self-test.txt   what was checked, and the results
#   checks/made.txt                          from what, on what
#
# It refuses a dirty working tree, runs the tests, builds the app, then
# runs its self-test on a copy outside the repository.
#
# Usage: tools/make-release.sh             a release (candidate)
#        tools/make-release.sh --bundle    after tagging: refresh the source bundle
#                                          (and SHA256SUMS) in the existing release

set -eu
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/.*static let string = "\(.*\)".*/\1/p' Sources/MacintoshBackupKit/Version.swift)
OUT=${MBU_RELEASES:-$HOME/MacPlusProjects/releases}/Macintosh-Backup-Utility-$VERSION
NAME="Macintosh Backup Utility"

sums() { (cd "$OUT" && find . -type f ! -name SHA256SUMS | sort | xargs shasum -a 256 > SHA256SUMS); }

if [ "${1:-}" = "--bundle" ]; then
    [ -d "$OUT" ] || { echo "no release at $OUT" >&2; exit 1; }
    git bundle create "$OUT/source/MacintoshBackup.bundle" --all 2> /dev/null
    git bundle verify "$OUT/source/MacintoshBackup.bundle" > /dev/null 2>&1
    sums
    echo "refreshed the source bundle: $(git describe --tags --always)"
    exit 0
fi

[ -z "$(git status --porcelain)" ] || { echo "commit (or stash) your changes first: a release is made from committed source" >&2; exit 1; }
[ -e "$OUT" ] && { echo "$OUT already exists: remove it, or change the version" >&2; exit 1; }
mkdir -p "$OUT/source" "$OUT/checks"
COMMIT=$(git rev-parse --short HEAD)
echo "== $NAME $VERSION, from $COMMIT"

echo "== the tests"
tools/test.sh > "$OUT/checks/tests.txt" 2>&1 || { tail -20 "$OUT/checks/tests.txt"; echo "the tests failed" >&2; exit 1; }
grep -E "Test run with" "$OUT/checks/tests.txt"

echo "== the app"
tools/build-app.sh > /dev/null

echo "== the self-test, on a copy outside the repository"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ditto "build/$NAME.app" "$WORK/$NAME.app"
(cd / && "$WORK/$NAME.app/Contents/MacOS/MacintoshBackup" --self-test) > "$OUT/checks/self-test.txt" 2>&1 \
    || { cat "$OUT/checks/self-test.txt"; echo "the self-test failed" >&2; exit 1; }
tail -1 "$OUT/checks/self-test.txt"

echo "== packaging"
ditto -c -k --keepParent "build/$NAME.app" "$OUT/Macintosh-Backup-Utility-$VERSION.zip"
cp Documentation/RELEASE-NOTES.md "$OUT/RELEASE-NOTES.md"
git bundle create "$OUT/source/MacintoshBackup.bundle" --all 2> /dev/null
git bundle verify "$OUT/source/MacintoshBackup.bundle" > /dev/null 2>&1
{
    echo "$NAME $VERSION, made $(date '+%Y-%m-%d %H:%M') from commit $COMMIT ($(git describe --tags --always))"
    echo "on $(sw_vers -productName) $(sw_vers -productVersion), $(sysctl -n hw.model), $(xcodebuild -version 2>/dev/null | head -1), $(swift --version 2>&1 | head -1)"
} > "$OUT/checks/made.txt"
sums
echo "== done: $OUT"
ls -l "$OUT"
du -sh "$OUT"
