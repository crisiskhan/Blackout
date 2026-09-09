# Blackout

Offline-first field vessel for iPhone and iPad. Native SwiftUI, iOS 18 Universal, bundle ID `com.crisiskhan.blackout`.

This tree is a **dump-and-replace** of the MapKit-era foundation. It implements BLACKOUT BUILD BIBLE v3: isolated Swift packages for every §3 module, generated §4 Field / Vision / map packs (TX and NM only), MapLibre Metal offline, graph router (Valhalla costing keys + OSM graph), party mesh + DTN, Field stepper, Vision guess pipeline, Watch companion, Live Activity, Action Button / Control Center.

There is **no account, no analytics, no live weather, no sat modem, no nationwide tiles outside TX and NM**.

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
- Switch TX WEST → NM pack. A pack for a state we ship no map for can never become active.
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

SOS is 56 pt, hold 800 ms. It sits on Comms, Live Activity, Action Button, and Control Center — not on browse MAP (lock-on on or off), Field, or ARMING. It offers system Emergency SOS and does **not** replace 911.

## Packs

Real OSM + DEM-derived contours, generated at build time (no runtime uplink). **Default open pack is TX WEST** — one walkable bbox with street names at walking zoom, a WALK/DRIVE graph built from those same streets, and USGS 3DEP hillshade. **NM** and **TX EAST** are walkable catalog packs with the same street/graph/attribution bar. They do not steal first-open. Only TX and NM ship; nothing in the tree carries FL or NY.

| Pack | Ground | Opens on | Wild overlay |
|---|---|---|---|
| TX WEST (default) | El Paso and Ciudad Juárez in the middle; north up the Anthony corridor through Las Cruces and Mesilla to the Organ Mountains, Santa Teresa and Sunland Park west, Socorro and Horizon City east, Samalayuca desert south | El Paso metro | Franklin Mountains |
| TX EAST (walkable) | Austin out to Pflugerville and Manor north, Elgin and Bastrop east, Buda and Kyle south | Austin metro | Lost Pines / Bastrop |
| NM (walkable) | Albuquerque with Corrales, Rio Rancho, Bernalillo and Placitas north, the Sandia crest east, South Valley and Isleta south, Rio Puerco west | Albuquerque metro | Sandia foothills |

A pack's bbox is the union of its slices; `home` is the metro slice, so the canvas opens on streets rather than on the empty midpoint of a wide box. `tools/test_walkable_next_pack.py` holds a coverage floor: a pack may grow past the ground it shipped with, never retreat inside it.

The wire-format and GeoJSON savings below go straight back into ground. Against what CPV 69 put on phones, TX WEST covers 3.6× the area, NM 4.0×, TX EAST 1.4× — and the three packs together still weigh 0.20 GB, because Douglas-Peucker at 1.1 m drops about a third of the vertices OSM ships without changing a line the canvas can draw.

| Pack | Bytes | Highway lines | Named streets | Graph |
|---|---|---|---|---|
| TX WEST | 58.0 MB | 156,241 | 53,804 | 237,242 nodes / 673,021 edges |
| NM | 56.8 MB | 144,884 | 35,716 | 221,604 nodes / 650,667 edges |
| TX EAST | 86.5 MB | 251,209 | 45,194 | 307,954 nodes / 874,075 edges |

### The walk graph walks

`oneway` is a rule about cars. Folding it into both travel modes left 37,863 of tx-west's walk edges (7.6%) one-directional, inventing detours — and on short blocks no path at all — purely on the side of the street the traffic runs against. Direction is per mode now: `oneway` binds cars, only `oneway:foot` binds feet, and `oneway=-1` means the reverse direction is the passable one rather than neither. `foot=no`, `access=private` and `motor_vehicle=no` keep routes nobody may take out of the graph. Rebuilt, tx-west is down to 3 one-way walk edges — the genuine `oneway:foot` ways — while car one-ways still stand at 9.6%.

`RouteGraph` carries a `GraphIndex` built once when a pack loads: adjacency per mode, node positions, and a 0.02° grid. Nearest-node reads the rings around a tap and stops when no further ring could hold anything closer. The search adds the straight line to the destination to its ordering, which only returns the true shortest path if no stored length undershoots the line it spans — so `pack_graph` measures each segment between the coordinates it actually ships and rounds up.

`graph.json` ships on wire v2 — nodes are dense indices into parallel lat/lon arrays and one `a, b, metres, flags` record carries both directions of a street. `pack_graph` in `tools/v3/fetch_packs.py` writes it and `PackedGraph` in `Packages/Router` reads it; change one and change the other.

Regenerate walkable packs (network at generate time only):

```bash
python3 -c "from tools.v3.fetch_packs import main; main(['tx-west'])"
python3 -c "from tools.v3.fetch_packs import main; main(['nm'])"
python3 -c "from tools.v3.fetch_packs import main; main(['tx-east'])"
```

`slim_packs` skips walkable packs (`tx-west`, `nm`, `tx-east`) so walking-zoom density is not cut back to a sticker extract.

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
# OSM/DEM extracts (network at generate time only). Walkable packs:
python3 -c "from tools.v3.fetch_packs import main; main(['tx-west'])"
python3 -c "from tools.v3.fetch_packs import main; main(['nm'])"
python3 -c "from tools.v3.fetch_packs import main; main(['tx-east'])"
# Do not slim walkable packs. generate_v3 still slims demoted catalog packs only.
python3 tools/generate_v3.py
```
