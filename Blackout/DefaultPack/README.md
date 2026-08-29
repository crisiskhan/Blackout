# DefaultPack — USGS Front Range sample

USGS National Map topo for a Denver / Front Range window. Public domain. Not a world map.

- Center 39.74, −105.3 · span 0.32 / 0.50 · z10–z12
- Tiles: `tiles/{z}/{x}/{y}.png` fetched at pack-build time from USGSTopo
- DEM / POI: `dem.json` and `poi.json` stay on disk for slope / towns UI
- Refresh tiles with `python3 tools/fetch_defaultpack_usgs.py`

Blackout paints these files locally. Map paint does not use MapKit or URLSession.
