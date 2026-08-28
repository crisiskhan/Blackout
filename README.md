# Blackout

Offline-first field app for iPhone and iPad. Native SwiftUI, iOS 18+, Universal, bundle ID `com.crisiskhan.blackout`.

This repository is a **foundation + wave 1.5** pass: it opens in Xcode, paints file-tile Map with a radar HUD, asks a bundled field guide, and keeps expeditions / breadcrumbs / SOS / sealed messages on-device. It is **not** a v1 ship of live mesh 1/N, stranger radio, vitals, map-pack relay, or auto-911.

## Open in Xcode (Crisis)

1. Install **Xcode 16** (iOS 18 SDK). This project uses Xcode 16 file-system synchronized groups.
2. Open `Blackout.xcodeproj`. Do not add CocoaPods, SPM remotes, Expo, or React Native.
3. Select the **Blackout** scheme, then an iPhone or iPad simulator / device.
4. Signing:
   - Target **Blackout** → Signing & Capabilities.
   - Enable **Automatically manage signing**.
   - Team: your Apple Developer team (Crisis Khan).
   - Bundle Identifier is already `com.crisiskhan.blackout`.
5. Build and run. First launch is not gated on login, network, or a permission grant. Local lock stays **off** until you enable it in Settings.

### Capabilities to enable

Nothing CloudKit, Push, Associated Domains, or Background Modes is required for this pass.

Leave the generated Info.plist usage strings as-is (Location When In Use, Camera, Microphone, Bluetooth, Motion, Face ID). They exist so deny-all is a supported field state — **do not** make them required at launch.

Optional later: **Background Modes → Location** only if you add always-on breadcrumbs. This pass restores tracking after kill while the app is in the foreground; it does not use Background Modes.

### Cold launch checks

- Airplane Mode on, no Apple ID wall: Map tab, dusk chrome, bundled Front Range sample (or the honest no-pack canvas), SOS FAB above the tab bar, gear.
- Deny location / camera / mic / Bluetooth: Guide ask (type), Skills, bundled map, messaging, and SOS still work. GPS denied uses **DEAD RECKONING** (compass + step length) from last-known or a manual pin. Long-press the map **or** tap **Drop pin at pack center**.
- Create an expedition, start breadcrumbs, arm SOS, kill the app, relaunch: all three still present (tracking flag + trail restore).
- Send-to-self message: decrypts after relaunch. SwiftData has ciphertext only — no plaintext body column. Compose drafts persist in UserDefaults.

## Verify DefaultPack is inside Blackout.app

The target copies `Blackout/DefaultPack` two ways so a synchronized-group miss cannot ship an empty pack:

1. **Copy Bundle Resources** — folder reference `Blackout/DefaultPack`.
2. **Run Script** “Copy DefaultPack into app bundle” (`ditto` into `$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/DefaultPack`). The script **fails the build** if `manifest.json` is missing.

After a Mac build:

```bash
# From the built app (Product → Show Build Folder in Xcode, or):
APP=$(find ~/Library/Developer/Xcode/DerivedData -name Blackout.app -type d | head -1)
test -f "$APP/DefaultPack/manifest.json" && echo "PACK OK $APP/DefaultPack"
ls "$APP/DefaultPack/tiles"
test -f "$APP/GuidePack/manifest.json" && wc -l "$APP/GuidePack/articles.jsonl"
```

On device/simulator: Map HUD reads `file tiles · no Apple base map`. If the pack is missing you get the **honest no-pack canvas**, not a spinner.

## Verify airplane map / zero Apple tile traffic (H1)

Map chrome does **not** instantiate Apple’s map view. Tiles come from `BundledTileOverlay` (`MKTileOverlay` subclass, `canReplaceMapContent = true`, `urlTemplate = nil`) via `loadTile` / `tileData` reading `file://` with `Data(contentsOf:)`. Pinching outside the pack swaps to the no-pack canvas (void + copy + Return to pack). Missing tiles paint void locally — never a gray spinner waiting on WAN.

On a Mac, airplane mode + run:

1. Enable Airplane Mode (and disable Wi-Fi on the simulator if needed).
2. Cold-launch Blackout. Map should paint DefaultPack in a few seconds.
3. Confirm **no Apple tile hosts**:
   - Xcode **Debug → Network** (or Instruments → Network): first-paint Map should show **no** connections to `gspe*.ls.apple.com`, `gscdn*.apple.com`, `configuration.ls.apple.com`, or `cdn*.apple-mapkit.com`.
   - Console.app filter `Blackout` + `ls.apple` / `mapkit` while on the Map tab.
   - Charles / Proxyman: no MapKit raster/vector tile URLs after launch onto Map.
4. Pinch/pan past the Front Range window: you must see the honest **Outside DefaultPack** canvas, not Apple gray tiles.

Source proof: `grep -R MKMapView Packages/Maps` is comments-only; there is no `MKMapView(` constructor. `./tools/audit_offline.sh` fails if `URLSession` or `MKMapView(` appears.

This Linux environment **cannot run xcodebuild**. The checks above are what a Mac airplane test must prove.

## Wave 1.5 (this pass)

Still airplane-first. Still no `URLSession`. Still no live mesh.

1. **Radar HUD** on Map — polar rings + 3s red.glow sweep on the file-tile terrain (never a black disc). Pinch still zooms the map. Heading-up / north-up. 0 peers: self + sweep only, no fake people. Members would be filled silver disks; strangers hollow rings. Tap self is not a peer sheet. `RadarPeerSheet` exists for later blips. Sweep haptic only if a blip would be crossed; sweep audio default **off**.
2. **Guide ask-engine** — Field tab: ask bar first, taxonomy chips, situation cards remain. Type now; on-device mic if permitted else type. `Blackout/GuidePack/` has **132** Rockies/Denver articles + inverted index (situation, water, fire, shelter, first aid, signaling, navigation, weather, plants/food, animals, tools, bushcraft, skills). Extractive snippets from the pack. Plants never get an edible verdict. `SystemLanguageModel` only if `availability == .available`, grounded on retrieved text, never first paint, never wait/download.
3. **Dead reckoning** — compass + step-length IMU when GPS is denied or cold. HUD chip **DEAD RECKONING**. Manual pin still works.
4. **Viewshed + slope** — toggles on Map chrome from bundled DEM. Copy says sample-quality, not USGS.
5. **SOS pictograms** — language-free siren, strobe, satellite/OS SOS, cancel on the confirm panel, plus existing slide. Still no auto-dial.
6. **Last ~2% battery** — SOS-only shell. RootView reads `battery.isCritical` and **unmounts** Map, Comms, Field, and Expedition (no TabView, no iPad sidebar, no gear, no Settings sheet). Banner `CRITICAL · SOS only`, last-known line or text **Drop pin** (writes the existing manual pin, does not paint the map), existing SOS confirm, 88pt FAB (hold 1.5s presents, slide commits, tap never fires). GPS/DR sensors stop. Plug-in restores the previous tab/sidebar. **Extreme Saver** is unchanged and *above* 2%: 4-tab chrome, SOS + coarse nav + radar. Last-2% does **not** write that profile.
7. **LiDAR range** — shown only when ARKit scene-depth / mesh reconstruction exists. Hidden otherwise. No error sheet.
8. **Missed check-in** — opt-in per expedition, default OFF. Timer lives on `AppContainer` so it keeps running if Expedition is unmounted (including last-2%). On miss: open SOS confirm. Does not auto-arm. Does not auto-911. No mesh notify.

Verify GuidePack in the built app:

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData -name Blackout.app -type d | head -1)
test -f "$APP/GuidePack/manifest.json" && echo "GUIDE OK"
wc -l "$APP/GuidePack/articles.jsonl"
```

## Architecture

```
Blackout app          composition root only (wires protocols)
        │
        ├── Features (never import each other)
        │     Messaging  VoicePTT  Maps  SOS  Expeditions  Field  Settings
        │
        ├── Kits (never import each other)
        │     DesignSystem  Crypto  Battery  Persistence  Location  Mesh
        │
        └── BlackoutCore     IDs, Envelope, PayloadKind, LocationFix,
                             BatteryPolicy, PermissionKind, protocols
```

- **Feature → Core + kits it needs.** Features talk persistence through `PersistenceServing`. SwiftData `@Model` types stay inside Persistence.
- **Kit → Core only.**
- **Mesh is a dumb pipe** (`Envelope` is opaque). This pass’s façade always reports **0 nearby** and treats that as success.
- **No URLSession** on the critical path.
- **No WKWebView, no analytics, no accounts, no CloudKit.** SwiftData `cloudKitDatabase: .none`.
- If SwiftData cannot open **on disk**, the UI shows `StoreFailure`. There is **no** in-memory fallback (a kill would wipe SOS / expeditions / messages).
- Crypto identity + key are one Keychain item. A failed `SecItemAdd` does not mint a new identity.

### Add a feature module

1. `Packages/YourFeature/Package.swift` with `platforms: [.iOS("18.0")]`.
2. Depend on `BlackoutCore` plus only the kits you need. Do not import other features.
3. Add the local package to `Blackout.xcodeproj` (Project → Package Dependencies → Add Local) **or** extend `tools/generate_project.py` and regenerate.
4. Link the library product on the Blackout app target.
5. Construct the root view from `AppContainer` / `RootView.swift` only.

Tokens live in `DesignSystem` as `enum BlackoutDS`. Do not fork `PermissionDenied(kind:reason:)`. Do not put a 56pt SOS control on the map; SOS is the 88pt FAB.

## Product chrome (this pass)

- **iPhone:** 4-tab `TabView` — Map (cold launch default), Comms, Field, Expedition. SOS is not a tab.
- **iPad regular:** 280pt sidebar, same four destinations. Expedition is a first-class lead surface. Compact falls back to the tab bar.
- **SOS FAB:** 88pt red circle. Overlay ignores the bottom safe area and pads `16 + tabBar(49) + homeIndicator(34)` on iPhone so the FAB sits **above the tab bar**, not in it. iPad regular: `16 + 34` (16pt above the home indicator). Cannot hide. Extreme Saver and last-2% SOS-only do not hide it.
  - Hold 1.5s → confirm cover (**unarmed**, haptic light). Tap never fires. Hold alone does not arm.
  - Slide to confirm → **log first**. If `logSOS` throws, the UI shows `StoreFailure` and SOS stays **unarmed**.
  - X before slide: dismiss, still unarmed. X after slide: dismiss; the local alert already went out.
  - After arm, primary control is **user-initiated OS Emergency SOS** (side + volume hardware gesture). **Never auto-dial 911.**
- **Field:** Ask bar first, then taxonomy, then situation cards. GuidePack is on-device. Vision never says edible. Unknown is valid. Extreme Saver and last-2% pause Vision.
- **Radar HUD:** Default on Map. Not a tab. Not a black disc.
- **Chat status:** Sealed | Queued | On mesh. Never delivery ticks. Message bodies are not printed or os_logged.
- **Dark / dusk only.** No light mode. Commits use metal, not red. Red is live/danger/SOS only.

## DefaultPack

`Blackout/DefaultPack/` is a **generated sample** of a Denver-adjacent Front Range window: a few z/x/y PNGs (zooms 10–12), a handful of POIs, and a small altitude table.

It is **not** a USGS extract, **not** OSM, and **not** a world map. Extra regions later via Files, never `URLSession`.

Regenerate (offline):

```bash
python3 tools/generate_project.py
```

That also rewrites `Blackout.xcodeproj` and the app icon.

## This-pass limitations

- No live Multipeer 1/N, no stranger radio blips, no vitals send, no map-pack relay (wave 2).
- No world map. Map rendering is the bundled file-tile canvas or the honest empty canvas.
- No auto-911, no fall detection / Auto-SOS. Missed check-in never auto-arms.
- No backend, no Expo, no third-party SDKs.
- Voice PTT is local record/playback only. Live PTT-over-mesh is wave 2.
- Extreme Saver (named profile, above 2%) does not hide SOS and does not disable coarse Navigate or the radar HUD.
- Last ~2% battery is SOS-only: radar HUD and coarse nav hide; SOS FAB stays. It is not Extreme Saver and does not rewrite the named profile.
- Breadcrumb tracking restores after kill in the foreground; it is not a Background Modes location session.
- Foundation Models run only when the OS already reports `.available`. This Linux environment cannot prove that path.

## QA v1 musts (fail closed)

| ID | Must |
|----|------|
| H1 | Core field flow works blocked/empty without network; no Apple map tiles on first paint |
| H2 | No crash/data loss on kill, airplane, permission deny |
| H3 | SOS can be armed and logged offline; log failure is visible and does not fake-arm |
| H4 | First launch is **not** gated on network, account, or required permission |
| H5 | Location features fail closed with an honest UI when GPS is denied (`PermissionDenied` + last-known / manual pin / compass-only — never a blank spinner) |

## Audit

```bash
./tools/audit_offline.sh
```

Fails if App sources use `URLSession`, `WKWebView`, analytics, CloudKit, `MKMapView(`, `fallbackInMemory`, or auto-911 on the boot path.
