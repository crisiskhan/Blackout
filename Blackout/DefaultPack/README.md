# DefaultPack — generated Front Range sample

This folder is a **generated sample**, not a USGS, OpenStreetMap, or commercial map extract.

- Region: Denver-adjacent Colorado Front Range (synthetic)
- Tiles: a handful of z/x/y PNGs at zooms 10–12
- DEM: small altitude table (`dem.json`)
- POI: a handful of labeled sample points (`poi.json`)

Blackout loads these over `file://` via `MKTileOverlay.loadTile` using local `Data(contentsOf:)`.
It does **not** fetch tiles at runtime. Extra regions are a later Files-based pass.

Do not treat elevations, POIs, or tile colors as authoritative.
