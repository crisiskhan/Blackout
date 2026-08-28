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
check 'MKMapView\(' 'no MKMapView constructor'
check 'fallbackInMemory' 'no in-memory SwiftData fallback'
check 'os_log\(|Logger\(|NSLog\(|print\(' 'no print/os_log (plaintext bodies)'

if grep -RIn --include='*.swift' 'loadTile' "$root/Packages/Maps" >/dev/null; then
  echo "OK   Maps overrides loadTile"
else
  echo "FAIL Maps missing loadTile override"
  fail=1
fi

if grep -q 'Copy DefaultPack into app bundle' "$root/Blackout.xcodeproj/project.pbxproj" \
  && grep -q 'DefaultPack in Resources' "$root/Blackout.xcodeproj/project.pbxproj"; then
  echo "OK   DefaultPack explicit copy + resources"
else
  echo "FAIL DefaultPack not in Copy Bundle Resources / script phase"
  fail=1
fi

if grep -q 'Copy GuidePack into app bundle' "$root/Blackout.xcodeproj/project.pbxproj" \
  && grep -q 'GuidePack in Resources' "$root/Blackout.xcodeproj/project.pbxproj"; then
  echo "OK   GuidePack explicit copy + resources"
else
  echo "FAIL GuidePack not in Copy Bundle Resources / script phase"
  fail=1
fi

if [[ -f "$root/Blackout/GuidePack/articles.jsonl" ]]; then
  count="$(grep -c . "$root/Blackout/GuidePack/articles.jsonl" || true)"
  if [[ "$count" -ge 40 ]]; then
    echo "OK   GuidePack articles ($count)"
  else
    echo "FAIL GuidePack article count $count (<40)"
    fail=1
  fi
else
  echo "FAIL GuidePack articles.jsonl missing"
  fail=1
fi

if grep -RIn --include='*.swift' 'try? persistence.logSOS\|try? persistence.appendBreadcrumb\|try? persistence.saveMessage' \
  "$root/Blackout" "$root/Packages" >/dev/null; then
  echo "FAIL swallowed persistence writes"
  fail=1
else
  echo "OK   no try? on logSOS/appendBreadcrumb/saveMessage"
fi

exit "$fail"
