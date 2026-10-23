#!/bin/zsh
# Builds an installer for the VoiceOver Audio Split app: build/VoiceOver Audio Split.pkg
# It puts the app in the Applications folder (macOS asks for an administrator
# password, as for any app installed there), removes the older script version
# if it's installed, and opens the app.
#
#   ./build.sh            build the installer
#   ./build.sh install    build it and install it on this Mac
#
# Needs Xcode. Signing:
#   * With "Developer ID Application" and "Developer ID Installer" certificates in
#     your keychain (Xcode > Settings > Accounts > Manage Certificates), they're used
#     automatically, and the installer opens on any Mac.
#   * Without them, the app gets a local signature: the installer works on the Mac
#     that built it, but other Macs block it.
#   * To notarize as well, save your notary details once with
#       xcrun notarytool store-credentials VoiceOverAudioSplit
#     and build with NOTARY_PROFILE=VoiceOverAudioSplit ./build.sh
# Or choose identities yourself with DEVELOPER_ID_APP and DEVELOPER_ID_INSTALLER.
set -euo pipefail
cd "${0:A:h}"

if [[ $EUID -eq 0 ]]; then
  echo "Run ./build.sh without sudo. It asks for your password itself when installing." >&2
  echo "(Built with sudo, files belong to the administrator account and can't be rebuilt.)" >&2
  exit 1
fi
BUILD="${BUILD_DIR:-build}"
mkdir -p "$BUILD"
if [[ ! -w "$BUILD" ]]; then
  echo "The $BUILD folder belongs to another account, probably from running with sudo." >&2
  echo "Remove it once with: sudo rm -rf \"$PWD/$BUILD\"" >&2
  exit 1
fi

APP_NAME="VoiceOver Audio Split"
PROJECT="App/VoiceOverAudioSplit.xcodeproj"
ENTITLEMENTS="App/Resources/VoiceOverAudioSplit.entitlements"
PAYLOAD="$BUILD/app-payload"
PKG="$BUILD/$APP_NAME.pkg"

identity() {
  security find-identity -v -p "${2:-codesigning}" 2>/dev/null | sed -n "s/.*\"\\($1: .*\\)\"/\\1/p" | head -1
}
APP_ID="${DEVELOPER_ID_APP:-$(identity "Developer ID Application")}"
INSTALLER_ID="${DEVELOPER_ID_INSTALLER:-$(identity "Developer ID Installer" basic)}"

rm -rf "$PAYLOAD" "$BUILD/app-component.pkg" "$BUILD/app-distribution.xml" "$PKG"
mkdir -p "$PAYLOAD/Applications"

echo "Building $APP_NAME…"
xcodebuild -project "$PROJECT" -scheme VoiceOverAudioSplit -configuration Release \
  -derivedDataPath "$BUILD/app" -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO build -quiet
cp -R "$BUILD/app/Build/Products/Release/$APP_NAME.app" "$PAYLOAD/Applications/"
APP="$PAYLOAD/Applications/$APP_NAME.app"
# For example 1.0.202610231930: the version, then the build number, so each build counts as newer.
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist").$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")"

if [[ -n "$APP_ID" ]]; then
  echo "Signing with $APP_ID"
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$APP_ID" "$APP"
else
  echo "No Developer ID Application certificate: signing for this Mac only."
  codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign - "$APP"
fi
codesign --verify --strict "$APP"

# Install exactly where we put it. Without this, the installer "updates" any other
# copy with the same app ID it finds (such as one in Xcode's build folder) instead,
# and nothing appears in Applications.
pkgbuild --analyze --root "$PAYLOAD" "$BUILD/app-components.plist" >/dev/null
python3 -c '
import plistlib, sys
path = sys.argv[1]
items = plistlib.load(open(path, "rb"))
for item in items:
    item["BundleIsRelocatable"] = False
    item["BundleOverwriteAction"] = "upgrade"
plistlib.dump(items, open(path, "wb"))' "$BUILD/app-components.plist"

pkgbuild --root "$PAYLOAD" --component-plist "$BUILD/app-components.plist" \
  --scripts Installer/app/scripts --identifier com.fullcircleat.VoiceOverAudioSplit.pkg \
  --version "$VERSION" --install-location / "$BUILD/app-component.pkg" >/dev/null

cat > "$BUILD/app-distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>$APP_NAME</title>
  <welcome file="welcome.html" mime-type="text/html"/>
  <conclusion file="conclusion.html" mime-type="text/html"/>
  <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
  <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
  <volume-check>
    <allowed-os-versions><os-version min="14.2"/></allowed-os-versions>
  </volume-check>
  <choices-outline><line choice="default"/></choices-outline>
  <choice id="default" title="$APP_NAME"><pkg-ref id="com.fullcircleat.VoiceOverAudioSplit.pkg"/></choice>
  <pkg-ref id="com.fullcircleat.VoiceOverAudioSplit.pkg" version="$VERSION">app-component.pkg</pkg-ref>
</installer-gui-script>
EOF

productbuild_args=(--distribution "$BUILD/app-distribution.xml" --resources Installer/app/resources --package-path "$BUILD")
if [[ -n "$INSTALLER_ID" ]]; then
  echo "Signing the installer with $INSTALLER_ID"
  productbuild_args+=(--sign "$INSTALLER_ID")
fi
productbuild "${productbuild_args[@]}" "$PKG" >/dev/null

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  if [[ -z "$APP_ID" || -z "$INSTALLER_ID" ]]; then
    echo "Notarizing needs both Developer ID certificates." >&2
    exit 1
  fi
  xcrun notarytool submit "$PKG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$PKG"
fi
echo "Built $PKG"
if [[ -z "$APP_ID" || -z "$INSTALLER_ID" ]]; then
  echo "Note: not signed with a Developer ID, so it only installs cleanly on this Mac."
fi

if [[ "${1:-}" == "install" ]]; then
  sudo installer -pkg "$PKG" -target /
fi
