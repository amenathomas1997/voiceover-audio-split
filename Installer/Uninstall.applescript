-- Uninstall VoiceOver Audio Split: stops the helpers and removes everything it installed.
set answer to display dialog "Remove VoiceOver Audio Split from this Mac? Your sound goes back to normal right away." buttons {"Cancel", "Uninstall"} default button "Uninstall" cancel button "Cancel" with title "Uninstall VoiceOver Audio Split"
do shell script "
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/local.voaudiosplit.keys.plist 2>/dev/null
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/local.voaudiosplit.login.plist 2>/dev/null
pkill -x VOAudioSplit; pkill -x VOAudioSplitKeys
rm -f ~/Library/LaunchAgents/local.voaudiosplit.keys.plist ~/Library/LaunchAgents/local.voaudiosplit.login.plist
rm -rf ~/Library/Application\\ Support/VOAudioSplit ~/Library/Logs/VOAudioSplitKeys.log
pkgutil --forget local.voaudiosplit.pkg >/dev/null 2>&1
rm -rf ~/Applications/VoiceOver\\ Audio\\ Split
true"
display dialog "VoiceOver Audio Split has been removed." buttons {"OK"} default button "OK" with title "Uninstall VoiceOver Audio Split"
