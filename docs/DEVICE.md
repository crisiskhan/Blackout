# DEVICE — one physical iPhone from Xcode 16.2

Repo: https://github.com/crisiskhan/Blackout
Branch: `cursor/blackout-bible-v3-64d0` (PR #4). Do not use `main`.
Project: `Blackout.xcodeproj`
Scheme: Blackout
Bundle id: `com.crisiskhan.blackout`
Xcode: 16.2
Destination: a physical iPhone (generic iOS device compile is CI only; this doc is device run).

## Steps

1. On a Mac with Xcode 16.2: clone the repo, `git fetch origin cursor/blackout-bible-v3-64d0 && git checkout cursor/blackout-bible-v3-64d0` (or checkout the PR #4 head). Confirm `git rev-parse --abbrev-ref HEAD` is that branch.
2. Open `Blackout.xcodeproj` (not a workspace). Select scheme **Blackout**.
3. Signing & Capabilities for targets Blackout and BlackoutWidgets (and BlackoutWatch only if you run that scheme): Automatically manage signing. Set Team to the Apple Developer team that owns `com.crisiskhan.blackout`. The pbxproj has `DEVELOPMENT_TEAM = ""` on purpose — pick Team in the Xcode UI for the local run; do not commit a team id. Scheme **Blackout** does not embed Watch; use scheme **BlackoutWatch** if you need the companion on a watch.
4. Connect the iPhone with a cable, unlock it, Trust This Computer if asked. Destination = that iPhone, not a simulator.
5. Confirm bundle id `com.crisiskhan.blackout` on the app target.
6. Required capabilities (must match Info.plist after this commit):
   - Bluetooth: `NSBluetoothAlwaysUsageDescription` + `NSBluetoothPeripheralUsageDescription`
   - Nearby / local network: `NSLocalNetworkUsageDescription` + `NSBonjourServices` array `_blackoutmesh._tcp`
   - Location when-in-use: `NSLocationWhenInUseUsageDescription` (not always)
   - Microphone: `NSMicrophoneUsageDescription`
   - Camera: `NSCameraUsageDescription`
   - Motion: `NSMotionUsageDescription`
7. Product → Run (Cmd-R). First launch may show permission dialogs; Deny is supported.
8. BEFORE tapping the ARMING unlock: iPhone Control Center — Airplane Mode ON, then Bluetooth ON. Wi-Fi stays off. Cell stays off. Then tap **INITIATE** on ARMING. Then score `docs/SOLO_QA.md`. For the next MAP still, score only the tip-60 bar in that file: full-height canvas, pack outline+puck, single MARK, no CALL SOS on browse MAP, no solid-red slab.
9. After the next Internal (tip 62 instrument, not this commit): on MAP, confirm one 44pt chip row (MARK / WALK / DRIVE / RULER / USNG / MAG/TRUE). Canvas is full-height with OSM credit and no style.json / MapKit debug overlay. Tap a street away from the puck (or a search hit). Confirm `DEST`. Tap **WALK** — a cyan line should follow streets from YOU to DEST. Repeat **DRIVE**. If the graph cannot route, WALK/DRIVE are disabled and/or chrome `OFF GRAPH` (no fake line). MARK is one row per coord. Road names stay at walking zoom. Graph was already in the tip-61 TX WEST pack (`Resources/Packs/tx-west/graph.json`).
10. NM (Albuquerque / Sandia) and TX EAST (Austin / Lost Pines) are walkable catalog packs. On ARMING, tap **NM** or **TX EAST** to open them. Streets, names, and a local WALK/DRIVE graph should be present at walking zoom with © OpenStreetMap. TX WEST stays default first-open until Crisis says switch.
11. Tip 68 (Speak finish + clean field). Score these on the MAP still:
    - Header reads `MAP  SPEAK  INSTRUMENTS  LOCK-ON` in whole words. Tip 67 showed `INSTRUME… LOCK-ON`; any `…` is a FAIL. Raise Settings → Display & Brightness → Text Size to the largest non-accessibility step: the controls wrap to a second line instead of clipping.
    - DEST + WALK, then SPEAK. Speak is **voice plus the cyan route line**: the phone says the whole turn-by-turn out loud and the route stays drawn on the map. The field gets one short line only — `SPEAK · 3 TURNS · 300 M`. The orange walk-script paragraph from the tip-67 stills must be gone; any multi-line text over the canvas is a FAIL.
    - Field chrome is at most three short lines: one deduped status line (`OFF GRAPH` / `TRUE NORTH` / `RULER …`), one `DEST … · BEARING …` line, one Speak status line. A bare `TRUE`, a doubled `OFF GRAPH`, or a Speak line left over from an old destination is a FAIL.
    - Pinch to walking zoom: silver street names draw on the streets. Tip 67 shipped a resolved style whose glyph URL was percent-escaped (`%7Bfontstack%7D`), so MapLibre fetched no glyphs and no name could draw. If names are still absent everywhere, say so — that is the glyph path, not the label size.
    - Regression guard: the cyan WALK line still follows streets, and MAP still keeps the screen awake.
