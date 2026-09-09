"""The routing graph as bytes the phone can use without parsing anything.

`graph.json` cost the app 1.7-2.2 seconds per pack on a simulator, nearly all
of it in JSONDecoder turning four million numbers into arrays, and it was the
largest file in every pack. None of that work was necessary: the reader wants
flat numeric arrays and the writer already has them.

So the file is those arrays, little-endian, in the exact order and layout the
router holds them. Loading is a length check and a copy. Links are stored in
compressed-sparse-row order — grouped by source node, with `rowStart` saying
where each node's group begins — so the reader does not have to sort or bucket
anything either.

Layout, all little-endian, every array 4-byte aligned:

    0   8   magic "BLKTGRF\\x01"
    8   4   uint32  version
    12  4   uint32  nodeCount
    16  4   uint32  linkCount
    20  4   uint32  reserved (0)
    24  4n  int32   latE7[nodeCount]        degrees x 1e7
        4n  int32   lonE7[nodeCount]
        4(n+1) uint32 rowStart[nodeCount+1] CSR row starts
        4L  uint32  target[linkCount]
        4L  uint32  millimetres[linkCount]
        1L  uint8   mode[linkCount]         bit0 walk, bit1 drive

Mirrored by GraphBinary in Packages/Router. Change one, change both.
"""

from __future__ import annotations

import struct
from array import array
from pathlib import Path

MAGIC = b"BLKTGRF\x01"
VERSION = 3
HEADER = struct.Struct("<8sIIII")

WALK_BIT = 1
DRIVE_BIT = 2

COORD_SCALE = 10_000_000  # e7: ~1.1 cm, finer than the 5 dp the packs carry.
METRE_SCALE = 1_000  # millimetres.


def _le(typecode: str, values) -> bytes:
    """Fixed-width array as little-endian bytes, whatever this machine is."""
    a = array(typecode, values)
    if struct.pack("=H", 1) != struct.pack("<H", 1):
        a.byteswap()
    return a.tobytes()


def _read(typecode: str, blob: bytes, offset: int, count: int) -> array:
    a = array(typecode)
    width = a.itemsize
    a.frombytes(blob[offset : offset + count * width])
    if struct.pack("=H", 1) != struct.pack("<H", 1):
        a.byteswap()
    return a


# How a segment record spells its permissions, per direction.
SEG_WALK_FORWARD = 1
SEG_DRIVE_FORWARD = 2
SEG_WALK_BACK = 4
SEG_DRIVE_BACK = 8


def csr_from_segments(node_count: int, segments: dict) -> dict:
    """Expand `(a, b, metres) -> flags` records into links grouped by source.

    A segment carries permissions for both directions, so it becomes up to two
    directed links. Grouping them by source is what lets the reader load the
    file without sorting or bucketing anything.
    """
    rows: list[list[tuple[int, int, int]]] = [[] for _ in range(node_count)]
    for (a, b, metres), flags in segments.items():
        if not (0 <= a < node_count and 0 <= b < node_count):
            continue
        mm = int(round(metres * METRE_SCALE))
        if mm <= 0 or mm > 0xFFFFFFFF:
            raise SystemExit(f"segment {a}->{b} is {metres} m, which will not fit the wire")
        forward = (WALK_BIT if flags & SEG_WALK_FORWARD else 0) | (DRIVE_BIT if flags & SEG_DRIVE_FORWARD else 0)
        backward = (WALK_BIT if flags & SEG_WALK_BACK else 0) | (DRIVE_BIT if flags & SEG_DRIVE_BACK else 0)
        if forward:
            rows[a].append((b, mm, forward))
        if backward:
            rows[b].append((a, mm, backward))

    row_start = [0] * (node_count + 1)
    target: list[int] = []
    millis: list[int] = []
    mode: list[int] = []
    for n in range(node_count):
        row_start[n] = len(target)
        # Sorted, so the same graph always encodes to the same bytes. Without
        # it a row's order followed whatever order the segments happened to be
        # visited in, and a rebuild that changed nothing still rewrote the file.
        for b, mm, bits in sorted(rows[n]):
            target.append(b)
            millis.append(mm)
            mode.append(bits)
    row_start[node_count] = len(target)
    return {"rowStart": row_start, "target": target, "millis": millis, "mode": mode}


def write(path: Path, lat: list[float], lon: list[float], row_start: list[int],
          target: list[int], millis: list[int], mode: list[int]) -> int:
    """Write one graph and return its size in bytes."""
    n = len(lat)
    if len(lon) != n:
        raise SystemExit("lat and lon disagree on how many nodes there are")
    if len(row_start) != n + 1:
        raise SystemExit("rowStart must have one more entry than there are nodes")
    link_count = len(target)
    if not (len(millis) == len(mode) == link_count):
        raise SystemExit("the three link arrays disagree on how many links there are")
    if row_start[-1] != link_count:
        raise SystemExit("rowStart does not end at the number of links")

    blob = bytearray(HEADER.pack(MAGIC, VERSION, n, link_count, 0))
    blob += _le("i", (int(round(v * COORD_SCALE)) for v in lat))
    blob += _le("i", (int(round(v * COORD_SCALE)) for v in lon))
    blob += _le("I", row_start)
    blob += _le("I", target)
    blob += _le("I", millis)
    blob += bytes(bytearray(mode))
    path.write_bytes(blob)
    return len(blob)


def read(path: Path) -> dict:
    """Read one back, as plain Python lists."""
    blob = path.read_bytes()
    if len(blob) < HEADER.size:
        raise SystemExit(f"{path} is too short to be a graph")
    magic, version, n, link_count, _ = HEADER.unpack_from(blob, 0)
    if magic != MAGIC:
        raise SystemExit(f"{path} is not a graph ({magic!r})")
    if version != VERSION:
        raise SystemExit(f"{path} is wire v{version}, this tool speaks v{VERSION} — rebuild the pack")

    want = HEADER.size + 4 * n * 2 + 4 * (n + 1) + 4 * link_count * 2 + link_count
    if len(blob) != want:
        raise SystemExit(f"{path} is {len(blob)} bytes, expected {want} for {n} nodes and {link_count} links")

    at = HEADER.size
    lat_e7 = _read("i", blob, at, n); at += 4 * n
    lon_e7 = _read("i", blob, at, n); at += 4 * n
    row_start = _read("I", blob, at, n + 1); at += 4 * (n + 1)
    target = _read("I", blob, at, link_count); at += 4 * link_count
    millis = _read("I", blob, at, link_count); at += 4 * link_count
    mode = _read("B", blob, at, link_count)

    return {
        "lat": [v / COORD_SCALE for v in lat_e7],
        "lon": [v / COORD_SCALE for v in lon_e7],
        "rowStart": list(row_start),
        "target": list(target),
        "metres": [v / METRE_SCALE for v in millis],
        "mode": list(mode),
    }


def edges(graph: dict) -> list[dict]:
    """Directed links as dicts, for guards that want to walk the graph."""
    out = []
    row_start = graph["rowStart"]
    for a in range(len(graph["lat"])):
        for i in range(row_start[a], row_start[a + 1]):
            bits = graph["mode"][i]
            out.append({
                "a": a,
                "b": graph["target"][i],
                "m": graph["metres"][i],
                "walk": bool(bits & WALK_BIT),
                "drive": bool(bits & DRIVE_BIT),
            })
    return out
