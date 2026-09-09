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
| TX WEST (default) | El Paso and Ciudad Juárez in the middle; north through Las Cruces and Mesilla past Hatch, west across the Potrillos to the Animas, east over the Hueco Mountains toward Sierra Blanca, south to Fabens, Tornillo and the Samalayuca desert | El Paso metro | Franklin Mountains |
| TX EAST (walkable) | Austin out to Pflugerville and Manor north, Elgin and Bastrop east, Buda and Kyle south | Austin metro | Lost Pines / Bastrop |
| NM (walkable) | Albuquerque in the middle; north through Bernalillo and Placitas to Santa Fe, east over the Sandia crest into the Estancia basin, south past Isleta to Los Lunas and Belen, west to the Rio Puerco | Albuquerque metro | Sandia foothills |

A pack's bbox is the union of its slices; `home` is the metro slice, so the canvas opens on streets rather than on the empty midpoint of a wide box. `tools/test_walkable_next_pack.py` holds a coverage floor: a pack may grow past the ground it shipped with, never retreat inside it.

### Streets ride as vector tiles

Each pack used to hold its whole street network in one `geojson` source, so
opening TX WEST meant MapLibre parsing 42 MB of text before it drew a line, and
the parse was the ceiling on how much ground a pack could carry. Streets now
ship as a PMTiles archive the vendored MapLibre reads natively, and the canvas
pays for the tiles under the viewport instead of the whole pack.

The spelling is not a guess. MapLibre links a PMTiles reader but documents no
local-file URL form, so a simulator was pointed at a real archive and asked:

```
pmtiles://file:///…/tx-west/osm.pmtiles   999 features drawn
pmtiles:///…/tx-west/osm.pmtiles            0 features drawn
```

`osm.geojson` is build input now, not cargo. Nothing outside tests ever read it,
so the resource copy step leaves it behind and the manifests stop counting it.
Every named street survives the cut, checked name by name against the source:
28,036 in, 28,036 out for TX WEST, and the same for the other two.

A vector source is addressed by layer, so a layer that names no `source-layer`
draws nothing and says nothing about it — the style still parses, the source
still loads, the streets are simply gone. `tools/test_tx_west_style.py` holds
both the style on disk and the layers the app injects at runtime to naming one.

Zoom decides what a tile carries, chosen from the data rather than a round
number. Service roads are a third of all geometry and read as noise above your
own block, so they arrive at z14. Tracks are 13% but fall in rural tiles holding
nothing else, and out there they are the only line to follow, so they arrive at
z12. Footways and paths come in at z13 with the residential grid.

The bytes that freed went back into ground. TX WEST covers 2.8× the area it did
before and NM 3.65×, while all three packs together drop from 201.0 MB to
89.9 MB — 93.4 MB once the water layers below are counted.

| Pack | Ships | of which streets | of which graph | of which water | Highway lines | Named streets | Graph |
|---|---|---|---|---|---|---|---|
| TX WEST | 33.8 MB | 15.8 MB | 9.8 MB | 1.6 MB | 173,901 | 60,153 | 263,512 nodes / 742,351 edges |
| NM | 32.8 MB | 13.9 MB | 11.7 MB | 1.0 MB | 210,634 | 52,195 | 312,157 nodes / 880,638 edges |
| TX EAST | 26.8 MB | 11.5 MB | 11.2 MB | 0.8 MB | 251,209 | 45,194 | 296,343 nodes / 848,575 edges |

### The walk graph walks

`oneway` is a rule about cars. Folding it into both travel modes left 37,863 of tx-west's walk edges (7.6%) one-directional, inventing detours — and on short blocks no path at all — purely on the side of the street the traffic runs against. Direction is per mode now: `oneway` binds cars, only `oneway:foot` binds feet, and `oneway=-1` means the reverse direction is the passable one rather than neither. `foot=no`, `access=private` and `motor_vehicle=no` keep routes nobody may take out of the graph. Rebuilt, tx-west is down to 3 one-way walk edges — the genuine `oneway:foot` ways — while car one-ways still stand at 9.6%.

`RouteGraph` carries a `GraphIndex` built once when a pack loads: adjacency per mode, node positions, and a 0.02° grid. Nearest-node reads the rings around a tap and stops when no further ring could hold anything closer. The search adds the straight line to the destination to its ordering, which only returns the true shortest path if no stored length undershoots the line it spans — so `pack_graph` measures each segment between the coordinates it actually ships and rounds up.

### The graph is bytes, not text

Once the streets moved to tiles, the graph was the largest file in every pack
and the slowest thing in the app: 13–15 MB of JSON that took **1.7–2.2 seconds**
a pack to load on a simulator, nearly all of it JSONDecoder turning four million
numbers into arrays. None of that work bought anything the bytes did not already
say. `graph.bin` is the arrays themselves — coordinates as `int32` at 1e7, links
grouped by source node, lengths as millimetres — laid out in the order the router
holds them, so loading is a length check and a copy. The scales are chosen so the
numbers land on the same `Double`s the JSON parsed to rather than merely near
ones, and the file is mapped rather than read, so pages fault in as touched.

In memory the graph was four dictionaries whose values were a fresh array per
node — about 700,000 heap allocations for NM, 76 MB to hold, and a hash on every
step of every search — even though the ids off the wire were already dense. Links
now sit in one compressed-sparse-row layout with a walk bit and a drive bit each,
so both modes share the storage instead of duplicating the larger half of it.

Ids are positions everywhere now, including for graphs built by hand, so a set
of ids that skips one leaves a hole rather than being renumbered under the
caller. Holes are NaN and stay out of the lookup grid; without that they would
have been nodes at 0,0 that every distant tap snapped to.

Rows are sorted, so the same graph always encodes to the same bytes. That is
what makes the next paragraph checkable.

`compact_graph` collapses degree-2 chains, and it is **not idempotent** —
collapsing a chain can leave its neighbours degree-2, so another pass finds more
to collapse. It belongs to the fetch, once. The rebuild path was calling it a
second time, which took TX WEST from 263,512 nodes to 251,334, then 249,254,
each pass quietly straightening another slice of the route drawn on the glass
and nothing saying so. Rebuild now re-encodes the graph and leaves its shape
alone, and `tools/test_graph_plan.py` fails if re-encoding a shipped pack
changes a single byte.

`tools/v3/graphbin.py` writes the file and `GraphBinary` in `Packages/Router`
reads it; change one and change the other, which a guard checks field by field.
The older `graph.json` wire v2 reader is still there so a pack predating this
still routes, but nothing generates it.

### Water is classified, not just drawn

The extract already carried every waterway and water polygon Overpass returned.
What it did not carry is *what kind of water each one is* in the words used on
the ground — tank, acequia, tinaja, playa. Those live in the name, and reading
names is where this gets dangerous:

```
tx-west  "Playa Lateral"       waterway=drain    an irrigation lateral
tx-west  "Playa Drain Canal"   waterway=canal    an irrigation canal
tx-west  "Mule Springs Creek"  waterway=stream   a creek
tx-west  "Cañon la Tinaja"     waterway=stream   a creek in a canyon
```

Eighty-two tx-west features carry "playa" in the name and not one of them is a
playa. So a name may name **standing** water only, never a channel: a tank, a
tinaja, a playa and a spring all sit still, and a line that moves is whatever
its tag says. The single exception is `acequia`, because an acequia *is* a
channel and the word is the channel's own name — all 247 across the three packs
are tagged ditch, canal, drain or stream and named "Acequia Madre", "Pueblo
Acequia", "Griegos Acequia".

Two files come out, because drawing and answering want different things.
`layers/water.geojson` is one mark per feature for the seven classes a line or
a fill cannot already say, small enough to sit in the style without putting a
parse back in front of the map opening. `layers/water.bin` is what a press is
measured against: every record including the creeks and the ponds, sampled
every 250 m along its length so a press in the middle of a three-kilometre
stream still finds it. As JSON that came to 13.3 MB for tx-west and would have
cost a parse of all of it to answer one press, so it is the same treatment the
graph got — arrays in the order the reader wants them, mapped rather than read.

| Pack | Records | Draw | Index | Populated classes |
|---|---|---|---|---|
| TX WEST | 19,547 | 0.65 MB | 0.99 MB | stream 12,106 · drain 3,114 · water 1,957 · canal 1,282 · ditch 522 · tank 218 · dam 166 · reservoir 65 · river 49 · acequia 34 · tap 24 · playa 8 · tinaja 1 · wetland 1 |
| NM | 14,599 | 0.40 MB | 0.57 MB | stream 5,625 · ditch 3,121 · drain 1,968 · water 1,944 · canal 665 · dam 437 · river 422 · acequia 213 · tap 125 · tank 48 · reservoir 25 · playa 3 · spring 2 · wetland 1 |
| TX EAST | 19,416 | 0.21 MB | 0.61 MB | water 9,446 · stream 5,675 · drain 1,649 · river 1,214 · ditch 615 · dam 553 · tap 249 · canal 8 · spring 6 · reservoir 1 |

Springs, playas and tinajas are thin on purpose. Overpass was never asked for
`natural=spring`, so the packs hold one; the rest of what the name search turns
up is creeks and irrigation laterals, and the classifier is built to leave those
alone rather than to make the table look fuller. The vocabulary is complete and
the data fills what it fills.

Zoom decides what the water says. The fill draws from the bottom of the range,
so far out the water is the shape of the ground and nothing else. Lines wait
for z11, which is where the tile archive actually starts carrying waterways —
below it that layer was promising geometry the file does not hold. The class
marks arrive at z14 and their names at z15. `WaterZoom` in `Packages/MapLibreMap`
and `tools/v3/water.py` hold the same four numbers, and a guard reads both.

The layers derive from the `osm.geojson` already in the tree, so regenerating
them needs no network and reproduces the shipped bytes exactly — which is what
a guard checks:

```bash
python3 -m tools.v3.water --refresh
git diff --stat Resources/Packs   # nothing
```

Regenerate walkable packs (network at generate time only):

```bash
python3 -c "from tools.v3.fetch_packs import main; main(['tx-west'])"
python3 -c "from tools.v3.fetch_packs import main; main(['nm'])"
python3 -c "from tools.v3.fetch_packs import main; main(['tx-east'])"
```

`slim_packs` skips walkable packs (`tx-west`, `nm`, `tx-east`) so walking-zoom density is not cut back to a sticker extract.

## Verify (Linux)

```bash
pip install -r tools/requirements.txt
./tools/audit_offline.sh
python3 tools/validate_v3.py
```

The Swift packages are iOS-only, so `swift test` refuses them and the suite
normally needs a Mac. `tools/swiftcheck` is a harness that points at the same
sources through symlinks with no platform floor, which runs everything that is
only Foundation — the water index, the map chrome, the pack catalogue:

```bash
swift test --package-path tools/swiftcheck   # 92 tests
```

It is not a product and CI does not run it; the iOS-only files drop out through
the `#if canImport(UIKit)` they carry. What it cannot cover is anything that
needs UIKit, SwiftUI or a renderer, which is what the simulator job is for.

## Verify (CI)

Two jobs, both required, both on every pull request whatever it targets.

`Blackout generic iOS device` compiles the app and runs all thirteen Python
guards. `Swift tests on a simulator` boots a simulator and runs every package
suite in `Packages/*/Tests`, discovered rather than listed.

That second job is newer than the tests it runs. Nothing had ever compiled
them — no CI invoked them, and the packages are iOS-only so `swift test`
cannot — so the whole Swift suite was decoration, and four packages' tests did
not build at all. What the compiler found once it was pointed at them:

- `PackManifest`, `PackCatalog` and the four `FieldCorpus` types are public and
  were decodable from disk but not constructible from any other module, because
  a struct's memberwise initialiser stays internal. That is what made the suites
  uncompilable.
- `PackStore` reordered the catalog through an initialiser that dropped
  `states`, so `switchTo`'s region-leak check read a nil list and waved through
  every pack in the catalog. `testSwitchRefusesAPackOffTheStatesWeShip` had been
  asserting otherwise, unexecuted, the whole time.

It also does the one check no file inspection can: it loads a real pack, waits
for the map to go idle, and counts the streets it drew.

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
