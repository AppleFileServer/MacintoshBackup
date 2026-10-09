#!/bin/sh
# Runs the library's tests (swift test), naming the SDK, which xcrun can't
# find by itself on this Mac.
set -eu
cd "$(dirname "$0")/.."
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
export SDKROOT
swift test "$@"
