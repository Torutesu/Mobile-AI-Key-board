#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
ios_dir=${script_dir:h}
team_id=${IOS_DEVELOPMENT_TEAM:-}
archive_path=${IOS_ARCHIVE_PATH:-/tmp/MobileAIKeyboard.xcarchive}
export_dir=${IOS_EXPORT_PATH:-/tmp/MobileAIKeyboard-TestFlight}
derived_path=${IOS_DERIVED_DATA_PATH:-/tmp/MobileAIKeyboard-derived}
auth_args=()
if [[ -n ${ASC_KEY_PATH:-} && -n ${ASC_KEY_ID:-} && -n ${ASC_ISSUER_ID:-} ]]; then
  auth_args=(
    -authenticationKeyPath "$ASC_KEY_PATH"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
  )
fi

if [[ -z "$team_id" ]]; then
  print -u2 "Set IOS_DEVELOPMENT_TEAM to the App Store Connect team that owns both bundle IDs and the App Group."
  exit 64
fi

cd "$ios_dir"
xcodegen generate --spec project.yml

xcodebuild archive \
  -project MobileAIKeyboard.xcodeproj \
  -scheme MobileAIKeyboard \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive_path" \
  -derivedDataPath "$derived_path" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$team_id" \
  -allowProvisioningUpdates \
  "${auth_args[@]}"

host_app="$archive_path/Products/Applications/MobileAIKeyboardHost.app"
extension_app="$host_app/PlugIns/MobileAIKeyboardExtension.appex"
[[ -d "$host_app" && -d "$extension_app" ]]

for product in "$host_app" "$extension_app"; do
  /usr/bin/codesign -d --entitlements :- "$product" >/tmp/"${product:t}".entitlements.plist 2>/dev/null
  /usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' /tmp/"${product:t}".entitlements.plist \
    | /usr/bin/grep -qx 'group.com.torutesu.mobileaikeyboard'
  [[ -f "$product/PrivacyInfo.xcprivacy" ]]
done

export_options=$(mktemp /tmp/MobileAIKeyboard-ExportOptions.XXXXXX.plist)
cp TestFlightExportOptions.plist "$export_options"
/usr/libexec/PlistBuddy -c "Set :teamID $team_id" "$export_options"

if [[ ${UPLOAD_TO_TESTFLIGHT:-0} == 1 ]]; then
  xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_dir" \
    -exportOptionsPlist "$export_options" \
    -allowProvisioningUpdates \
    "${auth_args[@]}"
  print "Upload submitted. Confirm processing status in App Store Connect before inviting testers."
else
  print "Archive and signed entitlement inspection passed: $archive_path"
  print "Set UPLOAD_TO_TESTFLIGHT=1 to export and upload this exact archive."
fi
