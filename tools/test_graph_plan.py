#!/usr/bin/env python3
"""Linux stand-in for Router GraphPlan unit tests (no Swift on this agent)."""
from __future__ import annotations

import json
import math
import re
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from v3 import graphbin  # noqa: E402
from v3.common import haversine_m  # noqa: E402
from v3.fetch_packs import (  # noqa: E402
    DRIVE_BACK,
    DRIVE_FORWARD,
    GRAPH_WIRE_VERSION,
    WALK_BACK,
    WALK_FORWARD,
    pack_graph,
    read_graph,
    write_graph_binary,
    unpack_graph,
    way_access,
    way_directions,
)

OFF_GRAPH = "OFF GRAPH"
ROUTE_LINE = ROOT / "Packages" / "MapLibreMap" / "Sources" / "MapLibreMap" / "RouteLine.swift"
ROUTER = ROOT / "Packages" / "Router" / "Sources" / "Router" / "Router.swift"


def route_block_cases() -> list[str]:
    src = ROUTE_LINE.read_text()
    body = src.split("public enum RouteBlock", 1)[1].split("public enum WalkDriveChip", 1)[0]
    return re.findall(r"^    case (\w+)$", body, flags=re.MULTILINE)


def block(has_pack: bool, has_graph: bool, has_dest: bool, dest_on_pack: bool):
    """Mirror of WalkDriveChip.block — first blocker wins, nil means draw."""
    if not has_pack:
        return "noPack"
    if not has_graph:
        return "noGraph"
    if not has_dest:
        return "noDestination"
    if not dest_on_pack:
        return "destinationOffPack"
    return None


def haversine(a: float, b: float, c: float, d: float) -> float:
    r = 6371000.0
    p1, p2 = math.radians(a), math.radians(c)
    dp, dl = math.radians(c - a), math.radians(d - b)
    x = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(x)))


class Graph:
    def __init__(self, nodes: dict, edges: list):
        self.nodes = nodes
        self.edges = edges


def nearest(graph: Graph, lat: float, lon: float):
    best = None
    for n in graph.nodes.values():
        d = haversine(lat, lon, n["lat"], n["lon"])
        if best is None or d < best[0]:
            best = (d, n["id"])
    return None if best is None else best[1]


def route(graph: Graph, src: int, dst: int, mode: str):
    adj: dict[int, list[tuple[int, float]]] = {}
    for e in graph.edges:
        ok = e["walk"] if mode == "walk" else e["drive"]
        if ok:
            adj.setdefault(e["a"], []).append((e["b"], e["m"]))
    dist = {src: 0.0}
    prev: dict[int, int] = {}
    seen: set[int] = set()
    q = [src]
    while q:
        u = min(q, key=lambda k: dist.get(k, math.inf))
        q.remove(u)
        if u in seen:
            continue
        seen.add(u)
        if u == dst:
            break
        for v, w in adj.get(u, []):
            alt = dist[u] + w
            if alt < dist.get(v, math.inf):
                dist[v] = alt
                prev[v] = u
                q.append(v)
    if dst not in dist:
        return None
    path = [dst]
    cur = dst
    while cur in prev:
        cur = prev[cur]
        path.append(cur)
    path.reverse()
    return path


def plan(graph: Graph | None, frm, to, mode: str):
    if graph is None or not graph.edges or not graph.nodes:
        return [], OFF_GRAPH
    a = nearest(graph, frm[0], frm[1])
    b = nearest(graph, to[0], to[1])
    if a is None or b is None:
        return [], OFF_GRAPH
    path = route(graph, a, b, mode)
    if not path:
        return [], OFF_GRAPH
    coords = [(graph.nodes[str(i)]["lat"], graph.nodes[str(i)]["lon"]) for i in path]
    if len(coords) < 2:
        return [], OFF_GRAPH
    return coords, ""


def walk_only() -> Graph:
    return Graph(
        {
            "1": {"id": 1, "lon": 0, "lat": 0},
            "2": {"id": 2, "lon": 0.01, "lat": 0},
            "3": {"id": 3, "lon": 0.02, "lat": 0},
        },
        [
            {"a": 1, "b": 2, "m": 100, "walk": True, "drive": False},
            {"a": 2, "b": 3, "m": 100, "walk": True, "drive": False},
        ],
    )


class GraphPlanTests(unittest.TestCase):
    def test_walk_two_hop_and_drive_off_graph(self):
        g = walk_only()
        self.assertEqual(route(g, 1, 3, "walk"), [1, 2, 3])
        self.assertIsNone(route(g, 1, 3, "drive"))
        coords, chrome = plan(g, (0, 0), (0, 0.02), "walk")
        self.assertEqual(chrome, "")
        self.assertEqual(len(coords), 3)
        self.assertEqual(coords[0][1], 0)
        self.assertEqual(coords[-1][1], 0.02)
        empty, off = plan(g, (0, 0), (0, 0.02), "drive")
        self.assertEqual(off, OFF_GRAPH)
        self.assertEqual(empty, [])

    def test_missing_and_empty_graph_are_honest(self):
        self.assertEqual(plan(None, (0, 0), (1, 1), "walk")[1], OFF_GRAPH)
        self.assertEqual(plan(Graph({}, []), (0, 0), (0, 0.02), "walk")[1], OFF_GRAPH)

    def test_nearest_and_no_fake_single_point_line(self):
        g = walk_only()
        self.assertEqual(nearest(g, 0, 0.009), 2)
        coords, chrome = plan(g, (0, 0), (0, 0), "walk")
        self.assertEqual(chrome, OFF_GRAPH)
        self.assertEqual(coords, [])


class WalkDriveChipTests(unittest.TestCase):
    def test_first_blocker_wins_and_ready_state_draws(self):
        self.assertIsNone(block(True, True, True, True))
        self.assertEqual(block(False, False, False, False), "noPack")
        self.assertEqual(block(True, False, False, False), "noGraph")
        self.assertEqual(block(True, True, False, False), "noDestination")
        self.assertEqual(block(True, True, True, False), "destinationOffPack")

    def test_every_block_case_has_a_sentence_and_a_plan_state(self):
        src = ROUTE_LINE.read_text()
        cases = route_block_cases()
        self.assertIn("noPath", cases)
        self.assertGreaterEqual(len(cases), 5)
        plan_switch = src.split("public var planChrome", 1)[1].split("public func chrome", 1)[0]
        chrome_switch = src.split("public func chrome(mode:", 1)[1].split("public enum WalkDriveChip", 1)[0]
        for name in cases:
            self.assertIn(f".{name}", plan_switch, f"{name} has no VoiceNav plan state")
            self.assertIn(f"case .{name}:", chrome_switch, f"{name} has no on-screen sentence")

    def test_chips_are_never_disabled_and_never_silent(self):
        src = ROUTE_LINE.read_text()
        self.assertIn("alwaysTappable = true", src)
        map_tab = (ROOT / "Blackout" / "MapTab.swift").read_text()
        inst = (ROOT / "Blackout" / "InstrumentsView.swift").read_text()
        tokens = (ROOT / "Packages" / "Tokens" / "Sources" / "Tokens" / "Tokens.swift").read_text()
        self.assertNotIn(".disabled(", map_tab)
        self.assertIn("BlackoutTokens.MapDock.allCases", map_tab)
        for chip in ("MARK", "WALK", "DRIVE", "SPEAK"):
            self.assertIn(f'return "{chip}"', tokens)
        for chip in ("RULER", "USNG", "MAG/TRUE"):
            self.assertIn(f'Button("{chip}")', inst)


class PackedGraphTests(unittest.TestCase):
    """The wire format must lose bytes, never turns."""

    def one_way_pair(self) -> dict:
        # 1 -> 2 both ways; 2 -> 3 forward only, like a one-way street.
        return {
            "engine": "osm-graph",
            "valhallaCosting": None,
            "nodes": {
                "11": {"id": 11, "lon": 0.0, "lat": 0.0},
                "22": {"id": 22, "lon": 0.01, "lat": 0.0},
                "33": {"id": 33, "lon": 0.02, "lat": 0.0},
            },
            "edges": [
                {"a": 11, "b": 22, "m": 100.0, "walk": True, "drive": True},
                {"a": 22, "b": 11, "m": 100.0, "walk": True, "drive": True},
                {"a": 22, "b": 33, "m": 100.0, "walk": True, "drive": False},
            ],
        }

    def test_round_trip_keeps_direction_and_mode(self):
        packed = pack_graph(self.one_way_pair())
        self.assertEqual(packed["v"], GRAPH_WIRE_VERSION)
        self.assertEqual(packed["lat"], [0.0, 0.0, 0.0])
        self.assertEqual(packed["lon"], [0.0, 0.01, 0.02])
        # Two segments, four numbers each: a, b, metres, flags.
        self.assertEqual(len(packed["e"]), 8)
        self.assertEqual(packed["e"][3], WALK_FORWARD | DRIVE_FORWARD | WALK_BACK | DRIVE_BACK)
        self.assertEqual(packed["e"][7], WALK_FORWARD)

        back = unpack_graph(packed)
        walkable = {(e["a"], e["b"]) for e in back["edges"] if e["walk"]}
        drivable = {(e["a"], e["b"]) for e in back["edges"] if e["drive"]}
        self.assertEqual(walkable, {(0, 1), (1, 0), (1, 2)})
        self.assertEqual(drivable, {(0, 1), (1, 0)})
        # A segment is as long as the coordinates it ships say it is. The router
        # steers A* by the straight line between those same points, so a stored
        # length under that line would cost it the shortest route.
        for e in back["edges"]:
            span = haversine_m(
                back["nodes"][str(e["a"])]["lat"],
                back["nodes"][str(e["a"])]["lon"],
                back["nodes"][str(e["b"])]["lat"],
                back["nodes"][str(e["b"])]["lon"],
            )
            self.assertGreaterEqual(e["m"], span)
            self.assertLess(e["m"] - span, 1.0)

    def test_a_one_way_street_never_becomes_two_way(self):
        packed = pack_graph(self.one_way_pair())
        back = unpack_graph(packed)
        self.assertNotIn((2, 1), {(e["a"], e["b"]) for e in back["edges"]})

    def test_swift_reader_agrees_with_the_python_writer(self):
        src = ROUTER.read_text()
        self.assertIn(f"static let wireVersion = {GRAPH_WIRE_VERSION}", src)
        for name, value in (
            ("walkForward", WALK_FORWARD),
            ("driveForward", DRIVE_FORWARD),
            ("walkBack", WALK_BACK),
            ("driveBack", DRIVE_BACK),
        ):
            self.assertIn(f"static let {name} = {value}", src, f"Swift disagrees on {name}")
        self.assertIn('case version = "v"', src)
        self.assertIn('case segments = "e"', src)
        self.assertIn("PackedGraph.self", src)

    def test_swift_reader_agrees_with_the_binary_writer(self):
        """The two ends of graph.bin have to spell the header the same way."""
        src = ROUTER.read_text()
        self.assertIn(f'static let version: UInt32 = {graphbin.VERSION}', src)
        self.assertIn(f"static let header = {graphbin.HEADER.size}", src)
        self.assertIn('Array("BLKTGRF".utf8) + [1]', src)
        self.assertEqual(graphbin.MAGIC, b"BLKTGRF\x01")
        # Bit for bit, or a one-way street changes direction on the phone.
        self.assertIn(f"static let walkBit: UInt8 = {graphbin.WALK_BIT}", src)
        self.assertIn(f"static let driveBit: UInt8 = {graphbin.DRIVE_BIT}", src)
        self.assertIn("/ 1e7", src)
        self.assertEqual(graphbin.COORD_SCALE, 10_000_000)
        self.assertIn("/ 1000", src)
        self.assertEqual(graphbin.METRE_SCALE, 1_000)

    def test_every_shipped_pack_is_on_the_wire_format(self):
        packs = ROOT / "Resources" / "Packs"
        graphs = sorted(packs.glob("*/graph.bin"))
        self.assertTrue(graphs, "no pack ships a binary graph")
        self.assertFalse(sorted(packs.glob("*/graph.json")), "a pack still carries the JSON graph")
        for path in graphs:
            pack = path.parent.name
            # read() checks magic, version and that the length matches the
            # counts in the header, so it raises on anything torn.
            g = graphbin.read(path)
            self.assertEqual(len(g["lat"]), len(g["lon"]), f"{pack} lat/lon disagree")
            self.assertEqual(g["rowStart"][0], 0, f"{pack} first row does not start at zero")
            self.assertEqual(g["rowStart"][-1], len(g["target"]), f"{pack} rows do not end at the link count")
            self.assertEqual(sorted(g["rowStart"]), list(g["rowStart"]), f"{pack} rows are out of order")
            self.assertTrue(all(0 <= t < len(g["lat"]) for t in g["target"]), f"{pack} links off the end")
            self.assertTrue(all(m > 0 for m in g["mode"]), f"{pack} carries a link nobody may take")

    def test_rebuilding_a_pack_leaves_its_graph_alone(self):
        """`--rebuild` re-encodes the graph; it must not reshape it.

        compact_graph collapses degree-2 chains, and running it over its own
        output finds more to collapse — 263,512 nodes to 251,334 to 249,254 on
        TX WEST. It belongs to the fetch, once. If the finalize path ever calls
        it again, every rebuild straightens another slice of the drawn route
        and nothing says so. This is that alarm.
        """
        for path in sorted((ROOT / "Resources" / "Packs").glob("*/graph.bin")):
            pack = path.parent.name
            before = path.read_bytes()
            graph = read_graph(path)
            out = Path(tempfile.mkdtemp()) / "graph.bin"
            write_graph_binary(out, graph)
            self.assertEqual(before, out.read_bytes(), f"{pack} changes when it is only re-encoded")

    def test_a_manifest_counts_the_graph_it_actually_ships(self):
        # Packing folds duplicate records, so a manifest written off the
        # pre-pack graph overstates the roads. Count what the phone loads.
        for path in sorted((ROOT / "Resources" / "Packs").glob("*/graph.bin")):
            pack = path.parent.name
            graph = read_graph(path)
            stats = json.loads((path.parent / "manifest.json").read_text())["stats"]
            self.assertEqual(stats["graphNodes"], len(graph["nodes"]), f"{pack} miscounts nodes")
            self.assertEqual(stats["graphEdges"], len(graph["edges"]), f"{pack} miscounts edges")


WALK_SET = {
    "path", "footway", "track", "residential", "unclassified", "service",
    "tertiary", "tertiary_link", "secondary", "secondary_link", "primary",
    "primary_link", "living_street", "pedestrian", "steps", "bridleway", "cycleway",
}
DRIVE_SET = {
    "motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link",
    "secondary", "secondary_link", "tertiary", "tertiary_link", "unclassified",
    "residential", "service", "living_street",
}


class WalkGraphTests(unittest.TestCase):
    def passable(self, tags: dict, highway: str) -> tuple[bool, bool, bool, bool]:
        walk, drive = way_access(tags, highway, WALK_SET, DRIVE_SET)
        walk_fwd, walk_back, drive_fwd, drive_back = way_directions(tags)
        return walk and walk_fwd, walk and walk_back, drive and drive_fwd, drive and drive_back

    def test_a_one_way_street_is_a_rule_about_cars_not_feet(self):
        self.assertEqual(self.passable({"oneway": "yes"}, "residential"), (True, True, True, False))
        self.assertEqual(self.passable({"junction": "roundabout"}, "tertiary"), (True, True, True, False))

    def test_only_oneway_foot_turns_a_pedestrian_around(self):
        tags = {"oneway": "yes", "oneway:foot": "yes"}
        self.assertEqual(self.passable(tags, "residential"), (True, False, True, False))

    def test_a_reversed_one_way_runs_backward_not_nowhere(self):
        self.assertEqual(self.passable({"oneway": "-1"}, "residential"), (True, True, False, True))

    def test_a_way_nobody_may_take_stays_out_of_the_graph(self):
        self.assertEqual(self.passable({"foot": "no"}, "footway"), (False, False, False, False))
        self.assertEqual(self.passable({"access": "private"}, "service"), (False, False, False, False))

    def test_feet_go_where_cars_cannot_and_the_reverse(self):
        self.assertEqual(self.passable({"motor_vehicle": "no"}, "pedestrian"), (True, True, False, False))
        self.assertEqual(self.passable({}, "steps"), (True, True, False, False))
        self.assertEqual(self.passable({"oneway": "yes"}, "motorway"), (False, False, True, False))

    def test_shipped_walk_graphs_are_two_way_on_the_ordinary_street(self):
        for path in sorted((ROOT / "Resources" / "Packs").glob("*/graph.bin")):
            graph = read_graph(path)
            walk = {(e["a"], e["b"]) for e in graph["edges"] if e["walk"]}
            if not walk:
                continue
            stranded = sum(1 for a, b in walk if (b, a) not in walk)
            share = stranded / len(walk)
            # Only oneway:foot and steps-with-direction should be one-way on
            # foot, and those are rare. A pack full of them means the car rule
            # leaked back into the walk graph.
            self.assertLess(share, 0.01, f"{path.parent.name}: {share:.1%} of walk edges are one-way")


if __name__ == "__main__":
    unittest.main()
