#!/bin/zsh
# Builds the universal app and packs it into build/EsyType-<version>.dmg for GitHub Releases.
# Not notarised (owner's decision, 2026-11-22): users open it once via System Settings ▸ Privacy & Security ▸ Open Anyway.
set -euo pipefail
cd "${0:A:h}/.."

Scripts/build-app.sh release
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Support/Info.plist)
DMG="build/EsyType-$VERSION.dmg"
STAGE=$(mktemp -d)
ditto build/EsyType.app "$STAGE/EsyType.app"
ln -s /Applications "$STAGE/Applications" # drag-to-install
rm -f "$DMG"
hdiutil create -volname "EsyType $VERSION" -srcfolder "$STAGE" -format UDZO -quiet "$DMG"
rm -rf "$STAGE"
hdiutil verify -quiet "$DMG"
shasum -a 256 "$DMG" | tee "$DMG.sha256"
