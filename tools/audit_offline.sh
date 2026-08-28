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
check 'WKWebViewConfiguration' 'no WKWebView config'
check 'FirebaseAnalytics|Amplitude|Mixpanel|TelemetryDeck|PostHog|Segment\.shared' 'no analytics SDKs'
check 'CKContainer|NSPersistentCloudKitContainer' 'no CloudKit'
check 'tel://911|telprompt:911' 'no auto-911'

if grep -RIn --include='*.swift' 'loadTile' "$root/Packages/Maps" >/dev/null; then
  echo "OK   Maps overrides loadTile"
else
  echo "FAIL Maps missing loadTile override"
  fail=1
fi

exit "$fail"
