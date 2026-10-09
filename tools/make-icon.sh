#!/bin/sh
# Makes Resources/AppIcon.icns from Resources/Icon/AppIcon.svg: renders it
# at 1024 x 1024 with headless Chrome (the MacMusic manual's copy, in
# ~/MacPlusProjects/manual-tools, or CHROME), scales it to every size
# macOS uses, and packs them with iconutil. Only needed when the design
# changes: the .icns is kept in the repository, so building the app
# doesn't need Chrome.
#
# Usage: tools/make-icon.sh

set -eu
cd "$(dirname "$0")/.."
CHROME=${CHROME:-$HOME/MacPlusProjects/manual-tools/chrome-headless-shell-mac-arm64/chrome-headless-shell}
[ -x "$CHROME" ] || { echo "headless Chrome not found: set CHROME" >&2; exit 1; }
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
"$CHROME" --headless --disable-gpu --hide-scrollbars --default-background-color=00000000 \
    --window-size=1024,1024 --screenshot="$WORK/icon.png" "file://$PWD/Resources/Icon/AppIcon.svg" > /dev/null 2>&1
SET=$WORK/AppIcon.iconset
mkdir "$SET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$WORK/icon.png" --out "$SET/icon_${size}x${size}.png" > /dev/null
    double=$((size * 2))
    sips -z $double $double "$WORK/icon.png" --out "$SET/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "made Resources/AppIcon.icns"
