# Feature 1 — on-pack routing contract

Blackout reads a Field Pack’s `routing/` directory. It does **not** generate graphs,
does **not** bake a graph into Denver `DefaultPack` or the `.ipa`, and does **not**
call `MKDirections`, `MKLocalSearch`, or `URLSession` for search / route / guidance /
reroute.

A later El Paso zip that includes `routing/` lights up without another code change.

## Discovery

Mounted pack root (Files / Field Packs / radio relay), not the app bundle sample.

```
manifest.json          key "routing": "routing/routing.json"
routing/routing.json
routing/graph.bin
routing/names.bin
routing/geometry.bin
```

If `routing/` is missing, `routing.json` is missing, magic mismatches, or the
binaries are truncated / count-mismatched: **honest empty**. Never invent a turn list.
Never WAN.

Denver `DefaultPack` has no `routing/`. El Paso Field Pack (`us-tx-el-paso`) is first.

## `routing.json` (`format`: `blackout-routing-v1`)

El Paso facts (reader accepts these keys; extra keys are ignored):

| key | El Paso |
|---|---|
| `format` | `blackout-routing-v1` |
| `profiles` | `[walk, drive]` |
| `bbox` | west −106.885, south 31.3619, east −106.085, north 32.1619 |
| `center` | 31.7619, −106.485 (optional) |
| `packId` | `us-tx-el-paso` (optional) |
| `nodeCount` | 237279 |
| `edgeCount` | 335665 |
| `walkEdgeCount` | 333626 |
| `driveEdgeCount` | 289072 |
| `onewayEdgeCount` | 52285 |
| `nameCount` | 23772 |
| `bidirectionalIfNotOneway` | `true` |
| `attribution` | ODbL text already in the pack — surface as caption, no new legal screen |

Optional `checksums` map (`graph.bin` / `names.bin` / `geometry.bin` → SHA-256 hex).
If present, a mismatch is honest empty.

Published El Paso binaries (do **not** vendor into git / DefaultPack / `.ipa`):

| file | bytes | sha256 |
|---|---|---|
| `graph.bin` | 10625538 | `2ac6f58c09d5d83f5a9f8ac791d37e81777922db4445a1672f4ecaeef6561917` |
| `names.bin` | 446213 | `21309ce4559fe2e6b7fc3af7798e3a91e387222bab79959e1fabf0ac023a2ffc` |
| `geometry.bin` | 9605206 | `7b2edbfebdc165634a4cb6e6104f4b7bdea30c2ffef92725eadc6bc2bcb97097` |

Size check: `16 + nodeCount*8 + edgeCount*26 = 10625538`.

## Binary layouts (little-endian, packed, unaligned)

### `graph.bin`

```
magic8          "BLRG0001"
u32             nodeCount
u32             edgeCount
nodes[nodeCount]:
  i32           lon_e7
  i32           lat_e7
edges[edgeCount]  (26 bytes, no padding):
  u32           from
  u32           to
  u32           nameId
  u16           flags
  u32           length_cm
  u32           walk_ms
  u32           drive_ms
```

Flags: bit0 = walk, bit1 = drive, bit2 = oneway forward-only (`from` → `to`).
If bit2 is clear, traverse both directions (`bidirectionalIfNotOneway`) and reverse
`geometry.bin` when traveling `to` → `from`.

Walk cost is `walk_ms` on edges with the walk bit. Drive cost is `drive_ms` on edges
with the drive bit. Skip edges missing the profile bit (drive never uses footpaths).

### `names.bin`

```
magic8          "BLNM0001"
u32             count
count × (u16 utf8len + bytes)
```

Index `0` is empty.

### `geometry.bin`

```
magic8          "BLGM0001"
u32             edgeCount     (same order as graph.bin edges)
per edge:
  u16           n
  n × (i32 lon_e7, i32 lat_e7)
```

## Router

There is no Apple offline routing API. Maps owns Swift A\* over this graph.
Mesh is a dumb pipe; `MapsRouting` never imports Mesh.

Reroute is on-pack only. Off-bbox / unsnappable: “Off pack. Bearing to destination.”
