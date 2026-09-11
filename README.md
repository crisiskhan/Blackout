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
Blackout app          ARMING, four tabs, contextual SOS, I AM OK
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
97.1 MB — and that figure now carries the water and land-cover layer as well.

| Pack | Ships | of which tiles | of which graph | Highway lines | Named streets | Graph |
|---|---|---|---|---|---|---|
| TX WEST | 33.2 MB | 16.8 MB | 9.8 MB | 173,901 | 60,153 | 263,512 nodes / 742,351 edges |
| NM | 34.0 MB | 15.9 MB | 11.7 MB | 210,634 | 52,195 | 312,157 nodes / 880,638 edges |
| TX EAST | 29.8 MB | 15.3 MB | 11.2 MB | 251,209 | 45,194 | 296,343 nodes / 848,575 edges |

### Hold a place to read the record

The map answers a thumb held still for 0.4s. The recogniser fails if the thumb
drifts more than 12pt, so a drag is still a drag and no card appears; a tap is
made to wait on the hold, so a press that becomes a card cannot also move the
destination out from under it. The probe reads a 44pt box rather than a point
— a thumb is not a pixel — and ranks what it finds. Water comes first, because
finding water is what holding a place is for: holding where a wash crosses a
road is a question about the wash, and the road already has its name written
along it. After that a record the survey named beats one it did not, because a
name means somebody stood at that exact thing. Then, between two named records,
take the smaller: a street is a line you aimed at, landcover is a sheet you
cannot miss. Between two unnamed ones take the ground, because out there the
biome is the answer and a ranch track is not.

That last pair of rules cost two passes to get right. `landuse=residential` is
drawn under every street in El Paso and Las Cruces, so ranking on kind alone
answered every hold downtown with the same anonymous ground. Ranking names
first fixed the unnamed case and left the named one: Gramercy Park still
answered for East Amador Avenue, because both are named and land sat above
street. Sampling 4,000 points across the tx-west pack, a street and a piece of
ground are both under the thumb 1.5% of the time, split about evenly between
the two cases — which is why it takes both rules and not either one.

The probe also has to look straight through the eight layers the app draws for
itself: the route line, the puck, and both pins. None of them carries a record,
and a hold that read the pin it just dropped would answer "Open ground" over
the spring underneath it. The skip list is written by hand, so a guard resolves
both sides — the layers the code constructs and the ids the list names — and
fails either way round.

The card is content-sized and capped at half the **canvas**, and the held point
gets its own bright pin over the scrim, so the place is never behind the thing
describing it. The canvas is the ruler that matters: half an 852pt screen is
most of a 529pt map, and the first cut measured the screen, so the card landed
back on top of the pin the camera had just lifted clear. Squeezing it to the
map meant the content could no longer be `fixedSize` either — under a short
canvas the sentences give up lines so FIELD and MARK keep their 44pt rather
than being clipped off the bottom. The scrim over the rest of the canvas is
graded, 14% over the pin and 55% behind the card: flat, it dimmed the one thing
the card was talking about, which undid half the reason for capping the card at
all.

Tap the dim map or swipe down to close. The swipe is on the whole canvas rather
than on the card, because a card-only swipe meant the top half of the screen
answered the gesture with nothing, and a surface that ignores you is one people
decide is broken.

Two actions, FIELD and MARK. There is no third and there is no SOS: SOS is a
Comms button, and a thumb resting on a map is not a call for help. That rule
has a second half that is easy to miss. `.isModal` is the tidy way to write a
card over a map — VoiceOver stays inside it instead of wandering onto the
canvas — and it hides everything outside its own subtree, tab bar included, and
Comms is on the tab bar. So the tidy version put SOS out of reach for anyone
using a screen reader. The canvas is hidden from VoiceOver instead, which is
what the scrim already does for a thumb, and only the canvas.

`MARK` marks the held place rather than the fix, and carries the record's name
into the label. Marks merge by coordinate, so the card opens reading `MARKED`
when there is already one there — the button used to offer a mark it would not
make.

`FIELD` opens the card that answers that ground. Every reading names an ordered
route rather than one id: the state cards that describe that exact ground,
then the core card behind them. Texas wrote a heat island card — *"pavement, no
shade, and a party still moving in an El Paso, Austin, or Albuquerque
afternoon"* — and New Mexico wrote one about ice on rock, and each ships only
in its own state's book, so every hold used to fall back to one of five core
cards and a subdivision at three in the afternoon opened "Stop and locate".
FIELD now walks the route and takes the first card the loaded book has. Falling
through is the normal case, not a fault, so the last id on every route is a
core one and the tab cannot come up empty. Three routes so far: built-up ground
to the heat island, rock and peaks to ice on rock, and a track to the cattle
guard, because a track out here is a ranch road. Water never diverts — the `DO`
line just said treat it, so FIELD opens the treat tree and nothing else. A
guard reads the ids out of `Inspect.swift` and checks them against the shipped
books, because both sides are hand-written strings in two different languages.

Arriving there used to land on a menu. The tab drew all seventeen card titles
in a `List` and hung the open card's steps underneath them, which is fine when
you came to browse and useless when the map already chose: on a phone the list
ate the height and the answer was below the fold. It shows one card or the
list, never both, with `ALL CARDS` on the open card so a hold is not a one-way
door into it. Two things surfaced while moving it. Every card ships both
languages and the list read the locale while the steps did not, so a Spanish
reader picked a card by its Spanish title and got the instructions in English.
And `NEXT` on the last step called a `next()` that guards on `isLast`, so it
did nothing at all — it says `DONE` and closes.

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

Splitting the ink was only half of it. A tank is mapped both ways in OSM, as a
node or as an outline, and 302 of the 583 around El Paso came through as
outlines. `water-points` is a circle layer, which has nothing sensible to do
with a ring; `water-fill` only takes `body` and `reservoir`; the line layers
only take channels. So a little over half the tanks in the pack matched no
layer at all — fetched, classed, in the tile, and nothing on the glass to hold.
Between 5m and 32m across they were never worth an outline at z14 anyway, so
the tiler centres spring, well, tank, tank_other and tap now, and the circle
draws every one of them at every zoom. The guard reads the circle layers out of
`style.json`, works out which classes each one claims, and fails if any of them
reach a tile as anything but a point.

Centring them was not enough to hold them. CI put a finger on what it thought was a real
`content=water` tank and the probe came back empty; the same
hold on a silent tank answered with the desert under it. The coordinates
had been reverse-projected from decoded tile pixels, and the decoder flips
Y, so the camera was as much as 1.7 km from the tank. The holds now use
the `representative_point` the tiler wrote, from the extract. Even on the
right point, `visibleFeatures` only returns what the style drew large enough
to hit, and a tank is a five-point ring. The hold now asks the pack's own
vector source for any spring, well, tank or tap inside the same 44pt box,
and the style carries a second circle the size of that box at 1% opacity —
zero reads as not drawn. The source is named `osm` so a pin the app drew
cannot answer.

Tinajas are not in this table because nothing in the record is tagged as one.
Searching both extracts for the word and its neighbours — *tinaja*, *charco*,
*hueco*, *ojo*, *aguaje* — returns 189 features and almost every one is a
street: `Calle Ojo Caliente`, `Hueco Tanks Road`, `Ojo de la Vaca Road`. Class
on a name and the map puts a rock pool in the middle of a subdivision.

What the record does know is the outline, and that is the whole difference
between a rock pool and a ranch reservoir. 230 unnamed `natural=water` polygons
across TX WEST and NM are under 100 m², and 45 of the 51 in TX WEST are outside
any mapped town. So the tiler measures each water body's longest side off the
whole record — before the tile clips it, or a pool sitting on a tile seam would
shrink at the join — and the card passes the measurement on and stops there.
Nine metres reads *"the outline is only about 9m across — a rock pool, a trough
and a dugout all read this way"*; seventy reads as a stock tank or a pool that
fills after rain. The size never moves `SURE`, because it is a fact about the
outline and not about the water.

Ground cover draws as a quiet fill from the archive floor and fades to almost
nothing by street zoom, where the streets carry the map; the inks are all
within a few points of black so they can never compete with a silver street or
a red route. Rivers and canals come in at z10 where you are choosing a
direction. A wash is drawn dashed, because a solid stroke would promise water
that is dry eleven months a year. Springs, wells and tanks are a ring at z12+,
not a badge — the ring says the record puts water here, not that it is good.
There are no animal icons, no edible dots, and no number anywhere that could be
read as safe to drink. Peaks, sinkholes and named trees are silver circles on
records the extract actually has. Holding woodland opens that pack's tree-use card first (the trees this
cover is), then plant-danger, cactus, animals, shelter, bite, meat you
already have. Holding scrub opens that pack's bite and mammal cards; holding a hole
opens the cave card, then cold. A named tree is tree-use, not the woodland dump. TX WEST names mesquite and javelina as range; TX EAST names copperhead and cottonmouth, not javelina. The hold prints `BOOK` as the unique procedures that
ground actually walks (`PLANT · ANIMAL · FOOD · BITE · SHELTER · FUNGI` on
woodland) and the button names the first card this pack's Field book ships —
a Texas peak is `FIELD · ANIMAL` then `NEXT · COLD`, not a COLD button for
an ice-on-rock card Texas does not have, and the DO line names coyote and deer
range, not ice. FIELD then walks the rest of the
route — tree-use,
cactus, animals, shelter, bite treatment, meat you already have — as `NEXT · PLANT` /
`NEXT · ANIMAL` / `NEXT · BITE` rather than dumping you on the list after the
first card. A FIELD still of this pack's mammal, tree, cactus or snake offers
the same procedure (`FIELD · ANIMAL` / `PLANT` / `BITE`). UNKNOWN and no
model do not invent a card. Animals of this country live in the Field book, not
as GPS pins.

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

That simulator is the only place some questions can be asked. Unit tests prove
the card reads a bag of tags correctly and the Python guards prove the tags are
in the pack, but between the two sit a tile archive, a style, a 44pt query and
a layer skip-list, and every one of them can silently answer nothing — which is
exactly where the 302 unholdable tanks were hiding. `HoldOnTheGlassTests` boots
the style the app boots, points the camera at four coordinates read back out of
the shipped archive, and calls the app's own `record(under:on:)`. Each
coordinate was picked by scanning the tiles for a feature with nothing of equal
rank within twice the probe box, so a pass is not luck.

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
