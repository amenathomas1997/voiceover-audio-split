#!/bin/zsh
# Builds the installer: build/VoiceOver Audio Split.pkg
#
#   ./build.sh            build the installer
#   ./build.sh install    build it and install it for the current user
#
# The package installs into the user's home folder (no admin password):
#   ~/Applications/VoiceOver Audio Split/
#     VO Audio Split.app                  the audio splitter (runs only while the split is on)
#     VO Audio Split Keys.app             Right Option + arrow shortcuts (always running)
#     Uninstall VoiceOver Audio Split.app
#     Scripts/                            double-clickable commands
#   ~/Library/LaunchAgents/local.voaudiosplit.keys.plist  (written by Installer/scripts/postinstall)
#
# Signing for other Macs: without a Developer ID, people must choose "Open Anyway"
# in System Settings > Privacy & Security the first time. To sign and notarize, set:
#   DEVELOPER_ID_APP="Developer ID Application: Name (TEAMID)"
#   DEVELOPER_ID_INSTALLER="Developer ID Installer: Name (TEAMID)"
#   NOTARY_PROFILE=<profile saved with: xcrun notarytool store-credentials>
set -euo pipefail
cd "${0:A:h}"

VERSION=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
SIGN_ID="${DEVELOPER_ID_APP:--}"
PAYLOAD="build/payload"
DEST="$PAYLOAD/Applications/VoiceOver Audio Split"
PKG="build/VoiceOver Audio Split.pkg"

rm -rf build
mkdir -p build/scripts "$DEST/Scripts"

# Compile the AppleScripts: .scpt for the shortcut helper, double-clickable apps for people.
python3 Scripts/make_scripts.py
for script in Scripts/*.applescript; do
  name="${${script:t}%.applescript}"
  osacompile -o "build/scripts/$name.scpt" "$script"
  osacompile -o "$DEST/Scripts/$name.app" "$script"
done
osacompile -o "$DEST/Uninstall VoiceOver Audio Split.app" Installer/Uninstall.applescript

# build_app <source dir> <executable> <bundle name> <Info.plist> [resources dir]
build_app() {
  local app="$DEST/$3.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  swiftc -O -target arm64-apple-macos14.2 -o "build/$2-arm64" "$1"/*.swift
  swiftc -O -target x86_64-apple-macos14.2 -o "build/$2-x86_64" "$1"/*.swift
  lipo -create -output "$app/Contents/MacOS/$2" "build/$2-arm64" "build/$2-x86_64"
  cp "$4" "$app/Contents/Info.plist"
  [[ -n "${5:-}" ]] && cp -R "$5" "$app/Contents/Resources/Scripts"
  codesign --force --options runtime --timestamp=none --sign "$SIGN_ID" \
    --identifier "$(plutil -extract CFBundleIdentifier raw "$4")" "$app"
}
build_app Sources/Split VOAudioSplit "VO Audio Split" Resources/Info.plist
build_app Sources/Keys VOAudioSplitKeys "VO Audio Split Keys" Resources/Keys-Info.plist build/scripts
for applet in "$DEST/Scripts/"*.app "$DEST/Uninstall VoiceOver Audio Split.app"; do
  codesign --force --sign "$SIGN_ID" "$applet"
done

# Keep the apps where we put them, even if another copy exists elsewhere on the Mac.
pkgbuild --analyze --root "$PAYLOAD" build/components.plist >/dev/null
python3 -c '
import plistlib, sys
path = sys.argv[1]
items = plistlib.load(open(path, "rb"))
for item in items:
    item["BundleIsRelocatable"] = False
plistlib.dump(items, open(path, "wb"))' build/components.plist

pkgbuild --root "$PAYLOAD" --component-plist build/components.plist \
  --scripts Installer/scripts --identifier local.voaudiosplit.pkg --version "$VERSION" \
  --install-location / build/component.pkg >/dev/null

cat > build/distribution.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>VoiceOver Audio Split</title>
  <welcome file="welcome.html" mime-type="text/html"/>
  <conclusion file="conclusion.html" mime-type="text/html"/>
  <domains enable_anywhere="false" enable_currentUserHome="true" enable_localSystem="false"/>
  <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
  <volume-check>
    <allowed-os-versions><os-version min="14.2"/></allowed-os-versions>
  </volume-check>
  <choices-outline><line choice="default"/></choices-outline>
  <choice id="default" title="VoiceOver Audio Split"><pkg-ref id="local.voaudiosplit.pkg"/></choice>
  <pkg-ref id="local.voaudiosplit.pkg" version="$VERSION">component.pkg</pkg-ref>
</installer-gui-script>
EOF

productbuild_args=(--distribution build/distribution.xml --resources Installer/resources --package-path build)
[[ -n "${DEVELOPER_ID_INSTALLER:-}" ]] && productbuild_args+=(--sign "$DEVELOPER_ID_INSTALLER")
productbuild "${productbuild_args[@]}" "$PKG" >/dev/null

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$PKG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$PKG"
fi
echo "Built $PKG"

if [[ "${1:-}" == "install" ]]; then
  installer -pkg "$PKG" -target CurrentUserHomeDirectory
fi
