#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
ios_dir=${script_dir:h}
team_id=${IOS_DEVELOPMENT_TEAM:-}
source_commit=${IOS_SOURCE_COMMIT:-$(git -C "$ios_dir" rev-parse HEAD)}
candidate_id=${IOS_CANDIDATE_ID:-${source_commit[1,12]}-local}
candidate_root=${IOS_CANDIDATE_ROOT:-/tmp/MobileAIKeyboard-${candidate_id}}
archive_path=${IOS_ARCHIVE_PATH:-${candidate_root}/MobileAIKeyboard.xcarchive}
export_dir=${IOS_EXPORT_PATH:-${candidate_root}/TestFlight}
derived_path=${IOS_DERIVED_DATA_PATH:-${candidate_root}/DerivedData}
evidence_path=${IOS_CANDIDATE_EVIDENCE_PATH:-${candidate_root}/candidate-evidence.json}
build_number=${IOS_BUILD_NUMBER:-}
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

if [[ ! "$source_commit" =~ ^[0-9a-f]{40}$ ]]; then
  print -u2 "IOS_SOURCE_COMMIT must be one exact 40-character lowercase Git SHA."
  exit 64
fi

if [[ -n "$build_number" && ! "$build_number" =~ ^[0-9]+$ ]]; then
  print -u2 "IOS_BUILD_NUMBER must contain decimal digits only."
  exit 64
fi

if [[ -n ${GITHUB_SHA:-} && "$source_commit" != "$GITHUB_SHA" ]]; then
  print -u2 "Candidate source commit does not match GITHUB_SHA."
  exit 65
fi

if [[ ${ALLOW_DIRTY_ARCHIVE:-0} != 1 && -n "$(git -C "$ios_dir" status --porcelain --untracked-files=normal)" ]]; then
  print -u2 "Refusing to archive a dirty worktree. Commit the exact candidate first or set ALLOW_DIRTY_ARCHIVE=1 for diagnostics only."
  exit 65
fi

if [[ ${UPLOAD_TO_TESTFLIGHT:-0} == 1 && (${#auth_args[@]} == 0 || -z ${ASC_APPLE_ID:-}) ]]; then
  print -u2 "TestFlight upload requires ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID, and ASC_APPLE_ID."
  exit 64
fi

build_overrides=()
if [[ -n "$build_number" ]]; then
  build_overrides=(CURRENT_PROJECT_VERSION="$build_number")
fi

mkdir -p "$candidate_root"

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
  MIK_SOURCE_COMMIT="$source_commit" \
  "${build_overrides[@]}" \
  -allowProvisioningUpdates \
  "${auth_args[@]}"

host_app="$archive_path/Products/Applications/MobileAIKeyboardHost.app"
extension_app="$host_app/PlugIns/MobileAIKeyboardExtension.appex"
[[ -d "$host_app" && -d "$extension_app" ]]

for product in "$host_app" "$extension_app"; do
  entitlements_path="${candidate_root}/${product:t}.entitlements.plist"
  /usr/bin/codesign -d --entitlements :- "$product" >"$entitlements_path" 2>/dev/null
  /usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$entitlements_path" \
    | /usr/bin/grep -qx 'group.com.torutesu.mobileaikeyboard'
  [[ -f "$product/PrivacyInfo.xcprivacy" ]]
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :MIKSourceCommit' "$product/Info.plist")" == "$source_commit" ]]
done

host_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$host_app/Info.plist")
extension_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$extension_app/Info.plist")
marketing_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$host_app/Info.plist")
build_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$host_app/Info.plist")
host_executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$host_app/Info.plist")
extension_executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$extension_app/Info.plist")
host_digest=$(shasum -a 256 "$host_app/$host_executable" | awk '{print $1}')
extension_digest=$(shasum -a 256 "$extension_app/$extension_executable" | awk '{print $1}')
archive_digest=$(
  cd "$archive_path"
  find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do
    shasum -a 256 "$file"
  done | shasum -a 256 | awk '{print $1}'
)
artifact_digest=$(printf '%s\n%s\n%s\n%s\n%s\n' "$source_commit" "$archive_digest" "$host_digest" "$extension_digest" "$build_version" | shasum -a 256 | awk '{print $1}')

mkdir -p "${evidence_path:h}"
evidence_plist=$(mktemp "${candidate_root}/CandidateEvidence.XXXXXX.plist")
plutil -create xml1 "$evidence_plist"
/usr/libexec/PlistBuddy -c 'Add :schema_version string mobile-ai-keyboard.testflight-candidate.v1' "$evidence_plist"
/usr/libexec/PlistBuddy -c 'Add :evidence_class string signed_archive_local_inspection' "$evidence_plist"
/usr/libexec/PlistBuddy -c 'Add :qualification_status string not_proven_until_physical_device' "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :candidate_id string $candidate_id" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :source_commit string $source_commit" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :artifact_digest string sha256:$artifact_digest" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :archive_digest string sha256:$archive_digest" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :host_executable_digest string sha256:$host_digest" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :extension_executable_digest string sha256:$extension_digest" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :host_bundle_id string $host_bundle_id" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :extension_bundle_id string $extension_bundle_id" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :marketing_version string $marketing_version" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :build_version string $build_version" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :team_id string $team_id" "$evidence_plist"
/usr/libexec/PlistBuddy -c 'Add :app_group string group.com.torutesu.mobileaikeyboard' "$evidence_plist"
plutil -convert json -o "$evidence_path" "$evidence_plist"
plutil -lint "$evidence_path" >/dev/null

export_options=$(mktemp "${candidate_root}/ExportOptions.XXXXXX.plist")
cp TestFlightExportOptions.plist "$export_options"
/usr/libexec/PlistBuddy -c "Set :teamID $team_id" "$export_options"

if [[ ${UPLOAD_TO_TESTFLIGHT:-0} == 1 ]]; then
  xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_dir" \
    -exportOptionsPlist "$export_options" \
    -allowProvisioningUpdates \
    "${auth_args[@]}"
  processing_status="$export_dir/processing-status.json"
  API_PRIVATE_KEYS_DIR="${ASC_KEY_PATH:h}" xcrun altool --build-status \
    --apple-id "$ASC_APPLE_ID" \
    --bundle-version "$build_version" \
    --bundle-short-version-string "$marketing_version" \
    --platform ios \
    --api-key "$ASC_KEY_ID" \
    --api-issuer "$ASC_ISSUER_ID" \
    --wait \
    --output-format json >"$processing_status"
  plutil -lint "$processing_status" >/dev/null 2>&1 || jq -e . "$processing_status" >/dev/null
  print "Upload and App Store Connect processing passed for $marketing_version ($build_version)."
  print "Processing evidence: $processing_status"
else
  print "Archive and signed entitlement inspection passed: $archive_path"
  print "Set UPLOAD_TO_TESTFLIGHT=1 to export and upload this exact archive."
fi
print "Candidate evidence: $evidence_path"
