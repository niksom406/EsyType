#!/bin/zsh
# Builds build/EsyType.app: universal (arm64 + x86_64), Hardened Runtime, signed.
# Usage: Scripts/build-app.sh [debug|release]   (default: release)
# Signing identity: $ESYTYPE_SIGN_IDENTITY, else the local "EsyType Dev" certificate if present, else ad-hoc ("-").
set -euo pipefail

cd "${0:A:h}/.."
CONFIG="${1:-release}"
APP="build/EsyType.app"
DEFAULT_IDENTITY=-
security find-certificate -c "EsyType Dev" >/dev/null 2>&1 && DEFAULT_IDENTITY="EsyType Dev"
IDENTITY="${ESYTYPE_SIGN_IDENTITY:-$DEFAULT_IDENTITY}"

# SwiftPM can't build several architectures at once without Xcode, so build each and merge with lipo.
for ARCH in arm64 x86_64; do
  swift build -c "$CONFIG" --arch "$ARCH" --product EsyType
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create \
  ".build/arm64-apple-macosx/$CONFIG/EsyType" \
  ".build/x86_64-apple-macosx/$CONFIG/EsyType" \
  -output "$APP/Contents/MacOS/EsyType"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
cp -R Resources/Licences "$APP/Contents/Resources/Licences"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# whisper.cpp (pinned in Package.swift): a universal dynamic framework, embedded and found via rpath.
mkdir -p "$APP/Contents/Frameworks"
ditto .build/artifacts/esytype/whisper/whisper.xcframework/macos-arm64_x86_64/whisper.framework \
  "$APP/Contents/Frameworks/whisper.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/EsyType"

# Ad-hoc signatures change on every build, so macOS forgets permissions after each rebuild; the self-signed
# "EsyType Dev" certificate keeps them (see TESTING.md). Releases still need a Developer ID.
ENTITLEMENTS=Support/EsyType.entitlements
if [[ "$IDENTITY" != "Developer ID Application"* ]]; then
  # shortcut: ad-hoc and self-signed identities have no Team ID, so library validation would refuse whisper.framework.
  # A Developer ID build signs both with one team and keeps validation on.
  ENTITLEMENTS="$(mktemp -d)/EsyType-dev.entitlements"
  cp Support/EsyType.entitlements "$ENTITLEMENTS"
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$ENTITLEMENTS"
fi
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP/Contents/Frameworks/whisper.framework"
codesign --force --options runtime --timestamp=none \
  --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
lipo -archs "$APP/Contents/MacOS/EsyType"
echo "Built $APP"
