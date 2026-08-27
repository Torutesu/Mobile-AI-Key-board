#!/bin/zsh
set -euo pipefail

if (( $# != 4 )); then
  print -u2 "Usage: $0 <profile> <bundle-id> <team-id> <app-group>"
  exit 64
fi

profile=$1
bundle_id=$2
team_id=$3
app_group=$4
decoded=$(mktemp /tmp/MobileAIKeyboard-Profile.XXXXXX.plist)
trap 'rm -f "$decoded"' EXIT

security cms -D -i "$profile" >"$decoded"
application_identifier=$(plutil -extract Entitlements.application-identifier raw "$decoded")
profile_team=$(plutil -extract TeamIdentifier.0 raw "$decoded")
expiration=$(plutil -extract ExpirationDate raw "$decoded")

[[ "$application_identifier" == "$team_id.$bundle_id" ]] || {
  print -u2 "Profile application identifier mismatch: expected $team_id.$bundle_id, got $application_identifier"
  exit 65
}
[[ "$profile_team" == "$team_id" ]] || {
  print -u2 "Profile team mismatch: expected $team_id, got $profile_team"
  exit 65
}
plutil -extract Entitlements.com.apple.security.application-groups json "$decoded" -o - \
  | jq -e --arg group "$app_group" 'index($group) != null' >/dev/null || {
    print -u2 "Profile does not authorize App Group $app_group"
    exit 65
  }

expiration_epoch=$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "$expiration" '+%s')
(( expiration_epoch > EPOCHSECONDS )) || {
  print -u2 "Provisioning profile expired at $expiration"
  exit 65
}

print "Validated profile for $bundle_id (expires $expiration)."
