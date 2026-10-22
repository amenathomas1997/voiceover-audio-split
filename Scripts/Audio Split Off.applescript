setMode("off")

-- Shared by all VoiceOver Audio Split scripts. Assign any of these scripts to a
-- key in VoiceOver Utility > Commanders > Keyboard (or Trackpad / NumPad).

property settingsFolder : "~/Library/Application\\ Support/VOAudioSplit"
property loginAgent : "~/Library/LaunchAgents/local.voaudiosplit.login.plist"
property balanceStep : 3
property balanceLimit : 30

on currentMode()
	try
		do shell script "pgrep -x VOAudioSplit"
	on error
		return "off"
	end try
	return readSetting("mode", "off")
end currentMode

on setMode(newMode)
	do shell script "pkill -x VOAudioSplit; sleep 0.3; true"
	writeSetting("mode", newMode)
	if newMode is not "off" then
		writeSetting("side", newMode)
		-- Found by bundle ID, so it works wherever the app is installed.
		do shell script "open -g -b local.voaudiosplit --args " & newMode
	end if
	if newMode is "left" then
		announce("Speech left, other sounds right")
	else if newMode is "right" then
		announce("Speech right, other sounds left")
	else
		announce("Audio split off")
	end if
end setMode

-- Positive balance: speech louder than other sounds. Negative: other sounds louder.
on changeBalance(delta)
	try
		set balance to (readSetting("balance", "0")) as integer
	on error
		set balance to 0
	end try
	if delta is 0 then
		set balance to 0
	else
		set balance to balance + delta
	end if
	if balance > balanceLimit then set balance to balanceLimit
	if balance < -balanceLimit then set balance to -balanceLimit
	writeSetting("balance", balance as text)
	do shell script "pkill -HUP -x VOAudioSplit; true"
	if balance is 0 then
		announce("Speech and other sounds equal volume")
	else if balance > 0 then
		announce("Speech " & balance & " decibels louder")
	else
		announce("Other sounds " & (-balance) & " decibels louder")
	end if
end changeBalance

on toggleLogin()
	try
		do shell script "test -f " & loginAgent
		do shell script "launchctl bootout gui/$(id -u) " & loginAgent & " 2>/dev/null; rm -f " & loginAgent
		announce("Audio split will not start at login")
	on error
		do shell script "mkdir -p ~/Library/LaunchAgents; cat > " & loginAgent & " <<EOF
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
	<key>Label</key>
	<string>local.voaudiosplit.login</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/open</string>
		<string>-g</string>
		<string>-b</string>
		<string>local.voaudiosplit</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF"
		announce("Audio split will start at login, speech " & readSetting("side", "left"))
	end try
end toggleLogin

on readSetting(settingName, defaultValue)
	try
		return do shell script "cat " & settingsFolder & "/" & settingName
	on error
		return defaultValue
	end try
end readSetting

on writeSetting(settingName, value)
	do shell script "mkdir -p " & settingsFolder & "; echo " & quoted form of (value as text) & " > " & settingsFolder & "/" & settingName
end writeSetting

on announce(message)
	try
		tell application "VoiceOver" to output message
	on error
		-- VoiceOver not running, or AppleScript control of VoiceOver is not allowed.
		say message
	end try
end announce
