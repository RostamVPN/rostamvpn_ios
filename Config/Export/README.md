# Export options

`xcodebuild archive` signs with a development identity even in Release; the
distribution signature is applied by `-exportArchive`, so `rostam.plist` decides
how the app ships. Fill in `teamID` (placeholder `REPLACE_WITH_TEAM_ID`) and,
for a team without an Xcode account signed in, add explicit `provisioningProfiles`
entries for the app and the tunnel extension.

```
Scripts/select-brand.sh rostam
xcodebuild archive -workspace rostamvpn.xcworkspace -scheme rostamvpn \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build/rostam -archivePath build/rostam/rostam.xcarchive \
  -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath build/rostam/rostam.xcarchive \
  -exportPath build/rostam/export \
  -exportOptionsPlist Config/Export/rostam.plist
```

`destination` is `export`, never `upload`. Nothing here uploads.

## Verify the artifact, never the log

On both the `.app` and the `.appex` inside the exported `.ipa`:

```
codesign -dvvv <target>                      # expect Apple Distribution
codesign -d --entitlements :- <target>       # expect ONE shared App Group
security cms -D -i <target>/embedded.mobileprovision
```

The App Group must be identical on the app and the extension. It is the only
channel between the two processes; a mismatch reads as a user who is never
entitled and a tunnel with no config, never as a crash. A manually created
provisioning profile with an empty `com.apple.security.application-groups`
exports successfully and is useless: the export takes its entitlements from the
profile.
