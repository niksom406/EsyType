#!/bin/zsh
# Runs `swift test`. With Command Line Tools only (no Xcode), Swift Testing lives outside the default
# search paths, so point the compiler and the test runner at it. With Xcode installed, plain `swift test` works.
set -euo pipefail
cd "${0:A:h}/.."
DEV=/Library/Developer/CommandLineTools/Library/Developer
if [[ -d "$DEV/Frameworks/Testing.framework" ]]; then
  exec swift test -Xswiftc -F -Xswiftc "$DEV/Frameworks" \
    -Xlinker -rpath -Xlinker "$DEV/Frameworks" -Xlinker -rpath -Xlinker "$DEV/usr/lib" "$@"
fi
exec swift test "$@"
