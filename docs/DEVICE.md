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
8. BEFORE tapping ACTIVATE: iPhone Control Center — Airplane Mode ON, then Bluetooth ON. Wi-Fi stays off. Cell stays off. The boot screen is the logo, not a pack menu. Wait until ACTIVATE is live, then tap it. It opens MAP. Then score `docs/SOLO_QA.md`. For the next MAP still, score only the tip-60 bar in that file: full-height canvas, pack outline+puck, single MARK, no CALL SOS on browse MAP, no solid-red slab.
9. After the next Internal (HUD chrome, not this commit): on MAP, the canvas is full-bleed under a four-cell dock (MARK / WALK / DRIVE / SPEAK) and overlay INSTRUMENTS / LOCK-ON (whole words, wrapping). RULER / USNG / MAG/TRUE are in INSTRUMENTS. Canvas has no OSM credit, no MapLibre mark, and no style.json / MapKit debug overlay. Tap a street away from the puck (or a search hit). Confirm DEST. Tap **WALK** — a silver line should follow streets from YOU to DEST. Repeat **DRIVE**. WALK/DRIVE are never disabled; if the graph cannot route, chrome `OFF GRAPH` (no fake line). MARK is one row per coord. Road names stay at walking zoom.
10. NM (Albuquerque / Sandia) and TX EAST (Austin / Lost Pines) are walkable catalog packs. On MAP → INSTRUMENTS → PACKS, tap **NM** or **TX EAST** to open them. Streets, names, and a local WALK/DRIVE graph should be present at walking zoom. No © OpenStreetMap on the glass. TX WEST stays default first-open until Crisis says switch.
11. Tip 68 (Speak finish + clean field). Score these on the MAP still:
    - HUD overlay: search on its own row; `INSTRUMENTS` + `LOCK-ON`/`LOCKED` wrap under it; `MARK` `WALK` `DRIVE` `SPEAK` as a four-cell dock at the thumb. No `INST`, no `INSTRUME…`. INSTRUMENTS opens the instruments sheet (RULER / USNG / MAG/TRUE live there). SPEAK is on the dock.
    - DEST + WALK, then SPEAK. Speak is **voice plus the silver route line**: the phone says the whole turn-by-turn out loud and the route stays drawn on the map. The field gets one short line only — `SPEAK · 3 TURNS · 300 M`. The orange walk-script paragraph from the tip-67 stills must be gone; any multi-line text over the canvas is a FAIL.
    - Field chrome is at most three short lines: one deduped status line (`OFF GRAPH` / `TRUE NORTH` / `RULER …`), one dest row of two chips (`BEARING` accent / `COORDINATES` silver) when there is somewhere to walk (dest, drawn route, or LOCK-ON). Tap expands the chip and the field shows the readout (`45°` or live GNSS `31.76190, -106.49000`); the other chip collapses to a smaller whole-word chip. Never a DEST pair; no GNSS is `NO FIX`. Idle MAP has no dest chips. One Speak status line. A bare `TRUE`, a doubled `OFF GRAPH`, dest chips with no dest, or a Speak line left over from an old destination is a FAIL.
    - Pinch to walking zoom: silver street names draw on the streets. Tip 67 shipped a resolved style whose glyph URL was percent-escaped (`%7Bfontstack%7D`), so MapLibre fetched no glyphs and no name could draw. If names are still absent everywhere, say so — that is the glyph path, not the label size.
    - MAP SEARCH: type or SAY as you type. Streets and peaks (`Montana Avenue`, Gardner Peak) come from the packed name index, not the 800-POI slice. Ranking runs off the glass so typing does not stall the HUD. Hits cap at five. Empty query is SEARCH (marks), not a dump. No hit is `NO MATCH`. Paste `31.76190, -106.49000` is one `COORDINATES` hit. SAY fills the field; it does not auto-pick DEST. Deny / PTT live / no on-device listen is `SAY FAILED`. Rows are HUD words (`STREET` / `PEAK` / `WATER`), not map tags. Range when YOU has a live fix. No credit on the glass.
    - Regression guard: the silver WALK line still follows streets, and MAP still keeps the screen awake.
