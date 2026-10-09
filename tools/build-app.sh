#!/bin/sh
# Builds "Macintosh Backup Utility.app" in build/ (Stage 3; W12): the
# release build of the app in a bundle with its Info.plist and icon,
# signed ad hoc.
#
# Usage: tools/build-app.sh

set -eu
cd "$(dirname "$0")/.."
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
export SDKROOT
VERSION=$(sed -n 's/.*static let string = "\(.*\)".*/\1/p' Sources/MacintoshBackupKit/Version.swift)
swift build -c release --product MacintoshBackup
BIN=$(swift build -c release --show-bin-path)/MacintoshBackup
APP="build/Macintosh Backup Utility.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacintoshBackup"
sed "s/@VERSION@/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "built $APP ($VERSION)"
