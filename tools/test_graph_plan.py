#!/usr/bin/env python3
"""Linux stand-in for Router GraphPlan unit tests (no Swift on this agent)."""
from __future__ import annotations

import math
import unittest


OFF_GRAPH = "OFF GRAPH"


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


if __name__ == "__main__":
    unittest.main()
