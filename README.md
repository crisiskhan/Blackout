# Blackout

Offline-first field vessel for iPhone and iPad. Native SwiftUI, iOS 18 Universal, bundle ID `com.crisiskhan.blackout`.

This tree is a **dump-and-replace** of the MapKit-era foundation. It implements BLACKOUT BUILD BIBLE v3: isolated Swift packages for every §3 module, generated §4 Field / Vision / map packs (TX NM FL NY only), MapLibre Metal offline, graph router (Valhalla costing keys + OSM graph), party mesh + DTN, Field stepper, Vision guess pipeline, Watch companion, Live Activity, Action Button / Control Center.

There is **no account, no analytics, no live weather, no sat modem, no nationwide tiles outside TX NM FL NY**.

## Open in Xcode (Crisis)

1. Install **Xcode 16** (iOS 18 SDK).
2. Open `Blackout.xcodeproj`.
3. Select the **Blackout** scheme.
4. Signing: Automatically manage signing, team Crisis Khan. Bundle ID is already `com.crisiskhan.blackout`.
5. **Do not bump `CURRENT_PROJECT_VERSION`** unless you intend a new TestFlight binary. This vessel keeps it at `1`.

This Linux builder **cannot run `xcodebuild` or archive an IPA**. Do not treat a green Python contract test as an Xcode 26 archive.

## Airplane success path

With a packed bbox on device and Airplane Mode on:

- Navigate the pack (MapLibre local style + OSM/graph; WALK / DRIVE / bearing fallback; DR when GNSS dies).
- Run a party net locally (ALL / 1:1, chips, PTT, DTN store). No sockets.
- Send RED and cancel RED.
- Run a 2 h water timer (OVERDUE plate is not SOS).
- Walk a Field stepper with pictures, SPEAK, SEND TO PARTY, Español.
- Point Vision at a plant: percent + lookalikes. Fungi default LEAVE IT. Never edible unlock.
- Switch TX → FL pack. Regional banners do not leak (no Adirondack ice in FL, no gator in NY).
- Export paper.

## Architecture

```
Blackout app          ARMING, four tabs, contextual SOS, I AM OK, cannot-do once
BlackoutWatch         lock-on, SOS, I AM OK, last pip, subject timer
BlackoutWidgets       Live Activity + Control Center CALL SOS
        │
        └── Packages/  isolated Swift modules (see PR checklist)
        └── Vendor/    MapLibre XCFramework, Opus 1.5.2, Valhalla-or-graph note
        └── Resources/ Packs, Field, Vision, Español table
```

SOS is 56 pt, hold 800 ms. It sits on lock-on, Comms, Live Activity, Action Button, and Control Center — not on Field browse or ARMING. It offers system Emergency SOS and does **not** replace 911.

## Packs

Real OSM + DEM-derived contours, generated at build time (no runtime uplink):

| Pack | Metro | Wild |
|---|---|---|
| TX WEST | El Paso | Franklin Mountains + El Paso TX+NM border union |
| TX EAST | Austin | Lost Pines / Bastrop |
| NM | Albuquerque | Sandia foothills |
| FL NORTH | Jacksonville | Timucuan / Big Talbot |
| FL SOUTH | Miami | Shark Valley / Everglades |
| NY METRO | Lower Manhattan | Jamaica Bay |
| NY UPSTATE | Albany | Adirondack High Peaks |

## Verify (Linux)

```bash
./tools/audit_offline.sh
python3 tools/validate_v3.py
```

## Verify (Mac)

- Airplane Mode. Cold launch. ARMING → cannot-do once → MAP.
- No Apple tile hosts. MapLibre local style only.
- Deny GPS / camera / mic: remaining surfaces still work.

## Workflows

`.github/workflows/asc-assign.yml` is **dispatch-only** App Store Connect assign. It does not compile, archive, or ship TestFlight. Do not add dead compile gates that assume old targets.

## Regenerating content

```bash
# OSM/DEM extracts (network at generate time only)
python3 -c "from tools.v3.fetch_packs import main; main()"
python3 tools/generate_v3.py
```
