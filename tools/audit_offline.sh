#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

check() {
  local pattern="$1"
  local label="$2"
  local hits
  hits="$(grep -RIn --include='*.swift' -E "$pattern" "$root/Blackout" "$root/Packages" || true)"
  if [[ "$pattern" == "URLSession" ]]; then
    hits="$(printf '%s\n' "$hits" | grep -v '/Packages/Packs/' || true)"
    hits="$(printf '%s\n' "$hits" | grep -v '^$' || true)"
  fi
  if [[ -n "$hits" ]]; then
    echo "FAIL $label"
    echo "$hits"
    fail=1
  else
    echo "OK   $label"
  fi
}

check 'URLSession' 'no URLSession outside Packs'
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
  if [[ "$count" -ge 132 ]]; then
    echo "OK   GuidePack articles ($count)"
  else
    echo "FAIL GuidePack article count $count (<132)"
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

if grep -q 'if container.battery.isCritical' "$root/Blackout/RootView.swift" \
  && grep -q 'CriticalSOSShell' "$root/Blackout/RootView.swift" \
  && grep -q 'iPhoneTabs' "$root/Blackout/RootView.swift"; then
  echo "OK   RootView last-2% chrome collapse"
else
  echo "FAIL RootView missing isCritical unmount of four destinations"
  fail=1
fi

if [[ -d "$root/Blackout/DefaultPack/tiles" ]] \
  && [[ -f "$root/Blackout/DefaultPack/tiles/10/211/387.png" ]]; then
  need="$(sed -n 's/.*"tileCount"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$root/Blackout/DefaultPack/manifest.json" | head -1)"
  count="$(find "$root/Blackout/DefaultPack/tiles" -name '*.png' | wc -l | tr -d '[:space:]')"
  if [[ -n "$need" && "$count" -ge "$need" ]]; then
    echo "OK   DefaultPack tiles/z/x/y.png present ($count, need $need)"
  else
    echo "FAIL DefaultPack PNG count $count (need $need)"
    fail=1
  fi
else
  echo "FAIL DefaultPack tiles missing"
  fail=1
fi

if grep -q 'copy_defaultpack.sh' "$root/Blackout.xcodeproj/project.pbxproj" \
  && grep -q 'tiles/10/211/387.png' "$root/Blackout.xcodeproj/project.pbxproj"; then
  echo "OK   DefaultPack copy phase probes tiles/z/x/y.png count"
else
  echo "FAIL DefaultPack copy phase does not probe PNG count / z/x/y layout"
  fail=1
fi

if grep -q 'func recenterToPackCoverage' "$root/Packages/Maps/Sources/Maps/OfflineMapView.swift" \
  && grep -q 'centerOn(latitude: pack.region.centerLatitude' "$root/Packages/Maps/Sources/Maps/OfflineMapView.swift" \
  && grep -q 'pinCameraToPack' "$root/Packages/Maps/Sources/Maps/OfflineMapView.swift"; then
  echo "OK   Recenter jumps to pack manifest center, not GPS"
else
  echo "FAIL Recenter missing pack-center jump (must not GPS-follow)"
  fail=1
fi

exit "$fail"
