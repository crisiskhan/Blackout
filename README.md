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
96.7 MB — and that figure now carries the water and land-cover layer as well.

| Pack | Ships | of which tiles | of which graph | Highway lines | Named streets | Graph |
|---|---|---|---|---|---|---|
| TX WEST | 33.1 MB | 16.8 MB | 9.8 MB | 173,901 | 60,153 | 263,512 nodes / 742,351 edges |
| NM | 34.0 MB | 15.9 MB | 11.7 MB | 210,634 | 52,195 | 312,157 nodes / 880,638 edges |
| TX EAST | 29.6 MB | 15.1 MB | 11.2 MB | 251,209 | 45,194 | 296,343 nodes / 848,575 edges |

### Hold a place to read the record

The map answers a thumb held still for 0.4s. The recogniser fails if the thumb
drifts more than 12pt, so a drag is still a drag and no card appears; a tap is
made to wait on the hold, so a press that becomes a card cannot also move the
destination out from under it. The probe reads a 44pt box rather than a point
— a thumb is not a pixel — and ranks what it finds. Water comes first, because
finding water is what holding a place is for: holding where a wash crosses a
road is a question about the wash, and the road already has its name written
along it. After that a record the survey named beats one it did not, and only
then does kind decide. That ordering is not cosmetic. `landuse=residential` is
a sheet laid under every street in El Paso, so ranking on kind alone answered
every hold downtown with the same anonymous ground; ranking names first returns
the street you aimed at, while an unnamed track in the desert still loses to
the biome around it.

The card is content-sized and capped at half the **canvas**, and the held point
gets its own bright pin over the scrim, so the place is never behind the thing
describing it. The canvas is the ruler that matters: half an 852pt screen is
most of a 529pt map, and the first cut measured the screen, so the card landed
back on top of the pin the camera had just lifted clear. Squeezing it to the
map meant the content could no longer be `fixedSize` either — under a short
canvas the sentences give up lines so FIELD and MARK keep their 44pt rather
than being clipped off the bottom. Tap the dim map or drag the card down to
close. Two actions,
FIELD and MARK. There is no third and there is no SOS: SOS is a Comms button,
and a thumb resting on a map is not a call for help. `MARK` marks the held
place rather than the fix, and carries the record's name into the label.

`SURE %` is confidence **in the record**, and the line beside it says why. It
is never a rating of the water. An unnamed `waterway=stream` reads *"the record
says stream and no more; out here that is usually dry between rains"* at 52% —
a statement about the survey, not the drink. What to do about the water is the
`DO` row's job, and Field's. `tools/test_hold_and_water.py` fails the build if
any word of permission — potable, drinkable, safe to drink, edible — reaches
either file, and if the card ever grows a third button or reaches for SOS.

It also keeps OpenStreetMap's line on screen. The credit lived in the canvas
footer, and raising a card hid the footer while the map kept drawing above it.
The three older guards all pass a file that does this, because they only check
that the string is somewhere in `MapTab.swift`; the new one checks it is inside
a branch that runs while a card is up.

### Water and ground

The first fetch asked for streets, waterways and lakes. It never asked for the
springs, wells and stock tanks that are the only water in most of this country,
nor for the scrub, sand and bare rock that say what the ground is. A second
narrow pass (`fetch_packs.py --resources`) fetches exactly those over the same
bbox and merges them into the extract already on disk. It is additive: the
router's graph is re-encoded from the bytes already there rather than rebuilt,
so all three `graph.bin` came out byte-identical, which is the proof the El
Paso streets did not move.

| Records added | TX WEST | NM |
|---|---|---|
| Springs / wells / tanks | 15 / 75 / 922 | 99 / 268 / 1,271 |
| Acequias and ditches | 522 | 3,326 |
| Drains | 3,121 | 1,968 |
| Canals and rivers | 1,343 | 1,095 |
| Desert, sand and rock | 809 | 2,045 |
| Built-up ground | 1,838 | 2,743 |

A tank is only water if the record says so. Around El Paso the pack holds 585
`man_made=storage_tank` records and **110** of them carry `content=water`; 470
say nothing at all and a few say fuel. The first cut drew every one with the
water ring and told you to treat it, which invents a supply that is as likely
to be diesel. `content` now travels from Overpass into the tile, the tiler
splits `tank` from `tank_other` on it, the style gives `tank_other` a grey ring
instead of the water one, and the card names an unlabelled tank as exactly
that: *"a tank is mapped here and nobody wrote down what is in it"*, SURE 42%,
leave it.

Tinajas are not in this table because they are not in the record. A handful of
features carry the word in a name — `Cañon la Tinaja` is a wash, `Cerros Ojo
Caliente` is a hill — and classing on a name would be the map guessing. An
unnamed `natural=water` polygon in this country reads *"mapped as standing
water with no name, which often means a stock tank or a seasonal pool"*, which
is what the record actually supports.

Ground cover draws as a quiet fill from the archive floor and fades to almost
nothing by street zoom, where the streets carry the map; the inks are all
within a few points of black so they can never compete with a silver street or
a red route. Rivers and canals come in at z10 where you are choosing a
direction. A wash is drawn dashed, because a solid stroke would promise water
that is dry eleven months a year. Springs, wells and tanks are a ring at z12+,
not a badge — the ring says the record puts water here, not that it is good.
There are no animal icons, no edible dots, and no number anywhere that could be
read as safe to drink.

Repairing geometry is part of tiling now. OSM has plenty of areas whose ring
crosses itself, and Shapely indexes them happily then throws on the first tile
that clips one — a single bad polygon near Austin killed a whole pack build.
`repair()` runs `make_valid` and keeps only the parts with the original's
dimension, so a broken polygon cannot come back as a stray line.

The tiler and the card keep two taxonomies in two languages, so a guard walks
every record the tiler can class and checks the reader branches on it. The
first version of that guard searched `Inspect.swift` for the tag's text and was
satisfied by `"residential"` appearing in the list of paved highway kinds —
while the land reader had no branch for `landuse=residential` at all. It also
was never called from `main()`. 8,107 polygons across the three packs — every
built-up part of El Paso, Las Cruces and Austin — were painted as town ground
and answered *"nothing is mapped at this point"* when held. `landuse=salt_pond`
was missing the same way. The guard now parses the branches the reader actually
takes, so a tag that only appears in an unrelated list no longer counts.

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

## Verify (CI)

Two jobs, both required, both on every pull request whatever it targets.

`Blackout generic iOS device` compiles the app and runs all twelve Python
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
