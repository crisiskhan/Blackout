"""Keep real OSM/graph/contours but drop duplicate bulk so git can hold the vessel."""
from __future__ import annotations

import json
from pathlib import Path

from .common import ROOT, write_json


def simplify_line(coords: list, step: int) -> list:
    if len(coords) <= 4:
        return coords
    out = coords[:: max(1, step)]
    if out[-1] != coords[-1]:
        out.append(coords[-1])
    return out


def slim_fc(path: Path, max_features: int, line_step: int) -> dict:
    data = json.loads(path.read_text())
    feats = []
    for f in data.get("features", []):
        g = f.get("geometry") or {}
        t = g.get("type")
        if t == "LineString":
            g = {**g, "coordinates": simplify_line(g.get("coordinates") or [], line_step)}
        elif t == "Polygon":
            rings = []
            for ring in g.get("coordinates") or []:
                rings.append(simplify_line(ring, line_step))
            g = {**g, "coordinates": rings}
        elif t == "MultiLineString":
            g = {**g, "coordinates": [simplify_line(c, max(1, line_step // 2)) for c in (g.get("coordinates") or [])][:80]}
        feats.append({**f, "geometry": g})
        if len(feats) >= max_features:
            break
    return {"type": "FeatureCollection", "features": feats, "attribution": data.get("attribution")}


def slim_graph(path: Path, max_edges: int) -> dict:
    g = json.loads(path.read_text())
    edges = g.get("edges") or []
    # keep both directions but cap
    edges = edges[:max_edges]
    used = {e["a"] for e in edges} | {e["b"] for e in edges}
    nodes = {k: v for k, v in (g.get("nodes") or {}).items() if int(k) in used or k in {str(i) for i in used}}
    # keys may be str ids
    nodes = {k: v for k, v in (g.get("nodes") or {}).items() if int(k) in used}
    return {
        "engine": g.get("engine"),
        "valhallaCosting": g.get("valhallaCosting"),
        "nodes": nodes,
        "edges": edges,
    }


def slim_dem(path: Path) -> dict:
    d = json.loads(path.read_text())
    grid = d.get("grid") or []
    lats = d.get("lats") or []
    lons = d.get("lons") or []
    step = 2
    d["lats"] = lats[::step]
    d["lons"] = lons[::step]
    d["grid"] = [row[::step] for row in grid[::step]]
    d["cellDegrees"] = (d.get("cellDegrees") or 0.015) * step
    return d


def main() -> None:
    root = ROOT / "Resources" / "Packs"
    catalog_packs = []
    for pack_dir in sorted(p for p in root.iterdir() if p.is_dir()):
        if (pack_dir / "osm.geojson").exists():
            write_json(pack_dir / "osm.geojson", slim_fc(pack_dir / "osm.geojson", 1800, 4))
        if (pack_dir / "graph.json").exists():
            write_json(pack_dir / "graph.json", slim_graph(pack_dir / "graph.json", 4000))
        if (pack_dir / "contours.geojson").exists():
            write_json(pack_dir / "contours.geojson", slim_fc(pack_dir / "contours.geojson", 80, 2))
        if (pack_dir / "dem.json").exists():
            write_json(pack_dir / "dem.json", slim_dem(pack_dir / "dem.json"))
        if (pack_dir / "pois.geojson").exists():
            write_json(pack_dir / "pois.geojson", slim_fc(pack_dir / "pois.geojson", 250, 1))
        for extra in pack_dir.glob("*.geojson"):
            if extra.name in {"osm.geojson", "contours.geojson", "pois.geojson"}:
                continue
            write_json(extra, slim_fc(extra, 400, 6))
        files = [p for p in pack_dir.rglob("*") if p.is_file()]
        size = sum(p.stat().st_size for p in files)
        man_path = pack_dir / "manifest.json"
        man = json.loads(man_path.read_text())
        man["bytes"] = size
        man["files"] = sorted(str(p.relative_to(pack_dir)) for p in files)
        write_json(man_path, man)
        catalog_packs.append(man)
        print(pack_dir.name, size)
    write_json(root / "catalog.json", {"schema": "blackout-packs-v3", "states": ["TX", "NM", "FL", "NY"], "packs": catalog_packs})


if __name__ == "__main__":
    main()
