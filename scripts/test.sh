#!/bin/bash
# Runs the DriveVerse core unit tests via SwiftPM.
#
# With full Xcode installed, a plain `swift test` works. On a machine with only
# the Command Line Tools, Testing.framework exists but is not on the default
# search paths, so we pass them explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."

if xcode-select -p 2>/dev/null | grep -q "CommandLineTools"; then
    FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
    LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
    exec swift test \
        -Xswiftc -F"$FW" \
        -Xlinker -F"$FW" \
        -Xlinker -rpath -Xlinker "$FW" \
        -Xlinker -rpath -Xlinker "$LIB" \
        "$@"
else
    exec swift test "$@"
fi
