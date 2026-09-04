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
3. Signing & Capabilities for targets Blackout, BlackoutWatch, BlackoutWidgets: Automatically manage signing. Set Team to the Apple Developer team that owns `com.crisiskhan.blackout`. The pbxproj has `DEVELOPMENT_TEAM = ""` on purpose — pick Team in the Xcode UI for the local run; do not commit a team id.
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
8. BEFORE tapping the ARMING unlock: iPhone Control Center — Airplane Mode ON, then Bluetooth ON. Wi-Fi stays off. Cell stays off. Then tap **ENTER** on ARMING (there is no INITIATE button; ENTER is the unlock). Then score `docs/SOLO_QA.md`.
