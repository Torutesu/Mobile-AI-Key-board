#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
ios_dir=${script_dir:h}
repo_root=${ios_dir:h:h}
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

head_commit=$(git -C "$ios_dir" rev-parse HEAD)
if [[ "$source_commit" != "$head_commit" ]]; then
  print -u2 "Candidate source commit does not match the checked-out HEAD."
  exit 65
fi

if [[ -n "$build_number" && ! "$build_number" =~ ^[0-9]+$ ]]; then
  print -u2 "IOS_BUILD_NUMBER must contain decimal digits only."
  exit 64
fi

if [[ -n ${GITHUB_SHA:-} && "$source_commit" != "$GITHUB_SHA" ]]; then
  print -u2 "Candidate source commit does not match GITHUB_SHA."
  exit 65
fi

if [[ -e "$candidate_root" ]]; then
  if [[ ! -d "$candidate_root" ]]; then
    print -u2 "Candidate root exists and is not a directory: $candidate_root"
    exit 65
  fi
  candidate_entries=("$candidate_root"/*(DN))
  if (( ${#candidate_entries[@]} > 0 )); then
    print -u2 "Refusing to reuse a non-empty candidate root: $candidate_root"
    exit 65
  fi
fi

if [[ ${UPLOAD_TO_TESTFLIGHT:-0} == 1 && ${ALLOW_DIRTY_ARCHIVE:-0} == 1 ]]; then
  print -u2 "Refusing TestFlight upload with ALLOW_DIRTY_ARCHIVE=1. Dirty archives are diagnostics-only."
  exit 65
fi

cd "$ios_dir"
initial_dirty=$(git -C "$ios_dir" status --porcelain --untracked-files=normal)
if [[ ${ALLOW_DIRTY_ARCHIVE:-0} != 1 && -n "$initial_dirty" ]]; then
  print -u2 "Refusing to archive a dirty worktree. Commit the exact candidate first or set ALLOW_DIRTY_ARCHIVE=1 for diagnostics only."
  exit 65
fi
if [[ -z "$initial_dirty" ]]; then
  xcodegen generate --spec project.yml
  if [[ -n "$(git -C "$ios_dir" status --porcelain --untracked-files=normal)" ]]; then
    print -u2 "Generated Xcode project differs from the committed project. Commit the generated project before archiving."
    exit 65
  fi
else
  print -u2 "Dirty diagnostic archive: preserving the existing Xcode project without regeneration."
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
  /usr/bin/codesign --verify --deep --strict "$product"
  product_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$product/Info.plist")
  if [[ "$product" == "$host_app" ]]; then
    expected_bundle_id='com.torutesu.mobileaikeyboard'
  else
    expected_bundle_id='com.torutesu.mobileaikeyboard.keyboard'
  fi
  [[ "$product_bundle_id" == "$expected_bundle_id" ]]
  application_identifier=$(/usr/libexec/PlistBuddy -c 'Print :application-identifier' "$entitlements_path")
  [[ "$application_identifier" == "$team_id.$expected_bundle_id" ]]
  [[ -f "$product/PrivacyInfo.xcprivacy" ]]
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :MIKSourceCommit' "$product/Info.plist")" == "$source_commit" ]]
done

host_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$host_app/Info.plist")
extension_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$extension_app/Info.plist")
[[ "$host_bundle_id" == 'com.torutesu.mobileaikeyboard' ]]
[[ "$extension_bundle_id" == 'com.torutesu.mobileaikeyboard.keyboard' ]]
host_profile="$host_app/embedded.mobileprovision"
extension_profile="$extension_app/embedded.mobileprovision"
[[ -f "$host_profile" && -f "$extension_profile" ]]
"$script_dir/validate-provisioning-profile.sh" "$host_profile" "$host_bundle_id" "$team_id" group.com.torutesu.mobileaikeyboard
"$script_dir/validate-provisioning-profile.sh" "$extension_profile" "$extension_bundle_id" "$team_id" group.com.torutesu.mobileaikeyboard
host_profile_plist="${candidate_root}/host-embedded-profile.plist"
extension_profile_plist="${candidate_root}/extension-embedded-profile.plist"
security cms -D -i "$host_profile" >"$host_profile_plist"
security cms -D -i "$extension_profile" >"$extension_profile_plist"
host_profile_uuid=$(plutil -extract UUID raw "$host_profile_plist")
extension_profile_uuid=$(plutil -extract UUID raw "$extension_profile_plist")
if [[ -n ${IOS_EXPECTED_HOST_PROFILE_UUID:-} && "$host_profile_uuid" != "$IOS_EXPECTED_HOST_PROFILE_UUID" ]]; then
  print -u2 "Archived host provisioning profile UUID does not match the validated input profile."
  exit 65
fi
if [[ -n ${IOS_EXPECTED_EXTENSION_PROFILE_UUID:-} && "$extension_profile_uuid" != "$IOS_EXPECTED_EXTENSION_PROFILE_UUID" ]]; then
  print -u2 "Archived extension provisioning profile UUID does not match the validated input profile."
  exit 65
fi
marketing_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$host_app/Info.plist")
build_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$host_app/Info.plist")
host_executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$host_app/Info.plist")
extension_executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$extension_app/Info.plist")
host_digest=$(shasum -a 256 "$host_app/$host_executable" | awk '{print $1}')
extension_digest=$(shasum -a 256 "$extension_app/$extension_executable" | awk '{print $1}')
archive_manifest="${candidate_root}/archive-sha256-manifest.txt"
(
  cd "$archive_path"
  find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do
    file_digest=$(shasum -a 256 "$file" | awk '{print $1}')
    file_size=$(stat -f '%z' "$file")
    printf '%s  %s  %s\n' "$file_digest" "$file_size" "$file"
  done
) >"$archive_manifest"
archive_manifest_digest=$(shasum -a 256 "$archive_manifest" | awk '{print $1}')
archive_digest=$(awk '{print $1}' "$archive_manifest" | shasum -a 256 | awk '{print $1}')
artifact_digest=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$source_commit" "$archive_digest" "$archive_manifest_digest" "$host_digest" "$extension_digest" "$build_version" | shasum -a 256 | awk '{print $1}')

mkdir -p "${evidence_path:h}"
evidence_plist=$(mktemp "${candidate_root}/CandidateEvidence.XXXXXX.plist")
plutil -create xml1 "$evidence_plist"
/usr/libexec/PlistBuddy -c 'Add :schema_version string mobile-ai-keyboard.testflight-candidate.v1' "$evidence_plist"
/usr/libexec/PlistBuddy -c 'Add :evidence_class string signed_archive_local_inspection' "$evidence_plist"
/usr/libexec/PlistBuddy -c 'Add :qualification_status string not_proven_until_physical_device' "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :candidate_id string $candidate_id" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :source_commit string $source_commit" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :artifact_digest string sha256:$artifact_digest" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :archive_artifact_digest string sha256:$artifact_digest" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :archive_digest string sha256:$archive_digest" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :archive_manifest_digest string sha256:$archive_manifest_digest" "$evidence_plist"
/usr/libexec/PlistBuddy -c 'Add :archive_manifest_path string archive-sha256-manifest.txt' "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :host_executable_digest string sha256:$host_digest" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :extension_executable_digest string sha256:$extension_digest" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :host_bundle_id string $host_bundle_id" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :extension_bundle_id string $extension_bundle_id" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :marketing_version string $marketing_version" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :build_version string $build_version" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :team_id string $team_id" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :host_profile_uuid string $host_profile_uuid" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :extension_profile_uuid string $extension_profile_uuid" "$evidence_plist"
/usr/libexec/PlistBuddy -c 'Add :app_group string group.com.torutesu.mobileaikeyboard' "$evidence_plist"
xcodegen_version=$(xcodegen --version | tr '\n' ' ')
xcode_version=$(xcodebuild -version | tr '\n' ' ')
/usr/libexec/PlistBuddy -c "Add :xcodegen_version string $xcodegen_version" "$evidence_plist"
/usr/libexec/PlistBuddy -c "Add :xcode_version string $xcode_version" "$evidence_plist"

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
  cp "$export_options" "$export_dir/ExportOptions.plist"
  ipa_paths=("$export_dir"/*.ipa(N))
  if (( ${#ipa_paths[@]} != 1 )); then
    print -u2 "Expected exactly one exported IPA, found ${#ipa_paths[@]}."
    exit 65
  fi
  ipa_path=${ipa_paths[1]}
  ipa_digest=$(shasum -a 256 "$ipa_path" | awk '{print $1}')
  /usr/libexec/PlistBuddy -c "Add :ipa_digest string sha256:$ipa_digest" "$evidence_plist"
  distribution_artifact_digest=$(printf '%s\n%s\n' "$artifact_digest" "$ipa_digest" | shasum -a 256 | awk '{print $1}')
  /usr/libexec/PlistBuddy -c "Set :artifact_digest sha256:$distribution_artifact_digest" "$evidence_plist"
  exported_root=$(mktemp -d "${candidate_root}/ExportedIPA.XXXXXX")
  ditto -x -k "$ipa_path" "$exported_root"
  exported_host="$exported_root/Payload/MobileAIKeyboardHost.app"
  exported_extension="$exported_host/PlugIns/MobileAIKeyboardExtension.appex"
  for product in "$exported_host" "$exported_extension"; do
    /usr/bin/codesign --verify --deep --strict "$product"
    /usr/bin/codesign -d --verbose=4 "$product" 2>&1 | /usr/bin/grep -Eq '^Authority=(Apple Distribution|iPhone Distribution):'
    /usr/bin/codesign -d --verbose=4 "$product" 2>&1 | /usr/bin/grep -qx "TeamIdentifier=$team_id"
    exported_entitlements="${candidate_root}/exported-${product:t}.entitlements.plist"
    /usr/bin/codesign -d --entitlements :- "$product" >"$exported_entitlements" 2>/dev/null
    exported_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$product/Info.plist")
    if [[ "$product" == "$exported_host" ]]; then
      expected_bundle_id='com.torutesu.mobileaikeyboard'
    else
      expected_bundle_id='com.torutesu.mobileaikeyboard.keyboard'
    fi
    [[ "$exported_bundle_id" == "$expected_bundle_id" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :application-identifier' "$exported_entitlements")" == "$team_id.$expected_bundle_id" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$exported_entitlements")" == 'group.com.torutesu.mobileaikeyboard' ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :MIKSourceCommit' "$product/Info.plist")" == "$source_commit" ]]
    [[ -f "$product/PrivacyInfo.xcprivacy" ]]
  done
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionAttributes:RequestsOpenAccess' "$exported_extension/Info.plist")" == true ]]
  "$script_dir/validate-provisioning-profile.sh" "$exported_host/embedded.mobileprovision" "$host_bundle_id" "$team_id" group.com.torutesu.mobileaikeyboard
  "$script_dir/validate-provisioning-profile.sh" "$exported_extension/embedded.mobileprovision" "$extension_bundle_id" "$team_id" group.com.torutesu.mobileaikeyboard
  exported_host_profile_plist="${candidate_root}/exported-host-profile.plist"
  exported_extension_profile_plist="${candidate_root}/exported-extension-profile.plist"
  security cms -D -i "$exported_host/embedded.mobileprovision" >"$exported_host_profile_plist"
  security cms -D -i "$exported_extension/embedded.mobileprovision" >"$exported_extension_profile_plist"
  exported_host_profile_uuid=$(plutil -extract UUID raw "$exported_host_profile_plist")
  exported_extension_profile_uuid=$(plutil -extract UUID raw "$exported_extension_profile_plist")
  if [[ "$exported_host_profile_uuid" != "$host_profile_uuid" || "$exported_extension_profile_uuid" != "$extension_profile_uuid" ]]; then
    print -u2 "Exported IPA provisioning profiles do not match the archived profiles."
    exit 65
  fi
  /usr/libexec/PlistBuddy -c "Add :exported_host_profile_uuid string $exported_host_profile_uuid" "$evidence_plist"
  /usr/libexec/PlistBuddy -c "Add :exported_extension_profile_uuid string $exported_extension_profile_uuid" "$evidence_plist"
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
  node "$repo_root/scripts/validate-app-store-processing.mjs" \
    --input "$processing_status" \
    --apple-id "$ASC_APPLE_ID" \
    --marketing-version "$marketing_version" \
    --build-version "$build_version"
  processing_status_digest=$(shasum -a 256 "$processing_status" | awk '{print $1}')
  /usr/libexec/PlistBuddy -c "Add :processing_status_digest string sha256:$processing_status_digest" "$evidence_plist"
  print "Upload and App Store Connect processing passed for $marketing_version ($build_version)."
  print "Processing evidence: $processing_status"
else
  print "Archive and signed entitlement inspection passed: $archive_path"
  print "Set UPLOAD_TO_TESTFLIGHT=1 to export and upload this exact archive."
fi
plutil -convert json -o "$evidence_path" "$evidence_plist"
plutil -lint "$evidence_path" >/dev/null
print "Candidate evidence: $evidence_path"
