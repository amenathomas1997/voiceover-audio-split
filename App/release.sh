#!/bin/zsh
# Builds a TestFlight / App Store build of VoiceOver Audio Split.
#
#   ./release.sh           archive and export the upload package to build/export (nothing leaves this Mac)
#   ./release.sh upload    archive and upload to App Store Connect, ready for TestFlight
#
# Each upload needs a higher build number: the script sets it to the current
# date and time, so you never have to edit it by hand.
# Needs: Xcode signed in to the Full Circle AT LLC team (Xcode > Settings > Accounts),
# and an app record for com.fullcircleat.VoiceOverAudioSplit in App Store Connect.
set -euo pipefail
cd "${0:A:h}"

DESTINATION=export
[[ "${1:-}" == "upload" ]] && DESTINATION=upload
BUILD_NUMBER=$(date +%Y%m%d%H%M)

command -v xcodegen >/dev/null && xcodegen --quiet
rm -rf build/VoiceOverAudioSplit.xcarchive build/export
mkdir -p build

xcodebuild -project VoiceOverAudioSplit.xcodeproj -scheme VoiceOverAudioSplit -configuration Release \
  -archivePath build/VoiceOverAudioSplit.xcarchive -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive | grep -E "error|ARCHIVE" || true
[[ -d build/VoiceOverAudioSplit.xcarchive ]] || { echo "Archive failed"; exit 1; }

cat > build/ExportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>$DESTINATION</string>
	<key>teamID</key>
	<string>9G2D7CDZ5D</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
EOF

xcodebuild -exportArchive -archivePath build/VoiceOverAudioSplit.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist -exportPath build/export -allowProvisioningUpdates

if [[ "$DESTINATION" == upload ]]; then
  echo "Uploaded build $BUILD_NUMBER. It appears in App Store Connect > TestFlight after processing (usually 5 to 30 minutes)."
else
  echo "Exported build $BUILD_NUMBER to build/export. Run ./release.sh upload to send it to TestFlight."
fi
