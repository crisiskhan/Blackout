#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

check() {
  local pattern="$1"
  local label="$2"
  local hits
  hits="$(grep -RIn --include='*.swift' -E "$pattern" "$root/Blackout" "$root/Packages" || true)"
  if [[ -n "$hits" ]]; then
    echo "FAIL $label"
    echo "$hits"
    fail=1
  else
    echo "OK   $label"
  fi
}

check 'URLSession' 'no URLSession'
check 'WKWebView' 'no WKWebView'
check 'FirebaseAnalytics|Amplitude|Mixpanel|TelemetryDeck|PostHog' 'no analytics SDKs'
check 'CKContainer|NSPersistentCloudKitContainer' 'no CloudKit'
check 'tel://911|telprompt:911' 'no auto-911'
check 'MKMapView\(' 'no MKMapView constructor'
check 'coming soon|TODO implement' 'no later-stubs'

if grep -q 'com.crisiskhan.blackout' "$root/Blackout.xcodeproj/project.pbxproj" \
  && grep -q 'CURRENT_PROJECT_VERSION = 1' "$root/Blackout.xcodeproj/project.pbxproj"; then
  echo "OK   vessel bundle + version"
else
  echo "FAIL vessel identity"
  fail=1
fi

if [[ -f "$root/Vendor/MapLibre/MapLibre.xcframework/Info.plist" ]]; then
  echo "OK   MapLibre xcframework"
else
  echo "FAIL MapLibre xcframework"
  fail=1
fi

python3 "$root/tools/validate_v3.py" || fail=1
exit "$fail"
