/* KHAN EYE desk. file:// Cesium only. No ion. No live feeds. */
(function () {
  "use strict";

  var pending = null;
  var viewer = null;
  var lastFit = -1;
  var lastAerial = "";
  var lastDem = "";
  var lastShade = "";
  var lastOsm = "";
  var lastWater = "";
  var lastContours = "";
  var lastGroundKey = "";
  var lastLook = "";
  var aerialLayer = null;
  var shadeLayer = null;
  var osmLayer = null;
  var waterSource = null;
  var contourSource = null;
  var holdTimer = null;
  var holdStart = null;
  var lastTapAt = 0;
  var lastTapPos = null;
  var pressedId = null;
  var demGrid = null;
  var GROUND = "#4a463c";

  function post(payload) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.khan) {
        window.webkit.messageHandlers.khan.postMessage(payload);
      }
    } catch (err) {
      /* airplane: the bridge is optional while the globe still draws */
    }
  }

  function blockIon() {
    if (Cesium.Ion) {
      Cesium.Ion.defaultAccessToken = "";
      if ("defaultServer" in Cesium.Ion) {
        Cesium.Ion.defaultServer = "";
      }
    }
    var names = ["fetch", "fetchJson", "fetchImage", "fetchArrayBuffer", "fetchText", "fetchBlob"];
    names.forEach(function (name) {
      if (!Cesium.Resource || !Cesium.Resource.prototype[name]) return;
      var orig = Cesium.Resource.prototype[name];
      Cesium.Resource.prototype[name] = function () {
        var url = String(this.url || "");
        if (/^https?:/i.test(url) || /ion\.cesium/i.test(url)) {
          return Promise.reject(new Error("NO PIPE"));
        }
        return orig.apply(this, arguments);
      };
    });
  }

  function xhr(url, type) {
    return new Promise(function (resolve, reject) {
      var req = new XMLHttpRequest();
      req.open("GET", url, true);
      if (type) req.responseType = type;
      req.timeout = type === "arraybuffer" ? 20000 : 8000;
      req.onload = function () {
        if (req.status === 0 || (req.status >= 200 && req.status < 300)) {
          resolve(req.response);
          return;
        }
        reject(new Error("NO PACK"));
      };
      req.onerror = function () {
        reject(new Error("NO PACK"));
      };
      req.ontimeout = function () {
        reject(new Error("NO PACK"));
      };
      req.send();
    });
  }

  function xhrImage(url) {
    return new Promise(function (resolve, reject) {
      var img = new Image();
      var to = setTimeout(function () {
        img.onload = img.onerror = null;
        reject(new Error("NO PACK"));
      }, 8000);
      img.onload = function () {
        clearTimeout(to);
        resolve(img);
      };
      img.onerror = function () {
        clearTimeout(to);
        reject(new Error("NO PACK"));
      };
      img.src = url;
    });
  }

  function packAsset(spec, name) {
    if (!spec || !spec.packId) return "";
    return "../Packs/" + spec.packId + "/" + name;
  }

  function emptyTile() {
    var c = document.createElement("canvas");
    c.width = 256;
    c.height = 256;
    return c;
  }

  function colorFor(condition, ghost) {
    var c;
    if (condition === "red") c = Cesium.Color.fromCssColorString("#E10600");
    else if (condition === "yellow") c = Cesium.Color.fromCssColorString("#E0A100");
    else c = Cesium.Color.fromCssColorString("#2EE67A");
    return ghost ? c.withAlpha(0.42) : c;
  }

  function cart(lat, lon, h) {
    return Cesium.Cartesian3.fromDegrees(lon, lat, h || 0);
  }

  function BufferSource(key, buffer) {
    this.key = key;
    this.buffer = buffer;
  }
  BufferSource.prototype.getKey = function () {
    return this.key;
  };
  BufferSource.prototype.getBytes = function (offset, length) {
    return Promise.resolve({ data: this.buffer.slice(offset, offset + length) });
  };

  function Pb(bytes) {
    this.b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
    this.i = 0;
    this.n = this.b.length;
  }
  Pb.prototype.u = function () {
    var n = 0;
    var s = 0;
    var v;
    while (this.i < this.n) {
      v = this.b[this.i++];
      n += (v & 127) * Math.pow(2, s);
      if (!(v & 128)) return n;
      s += 7;
    }
    return n;
  };
  Pb.prototype.bytes = function () {
    var n = this.u();
    var s = this.b.subarray(this.i, this.i + n);
    this.i += n;
    return s;
  };
  Pb.prototype.str = function () {
    var b = this.bytes();
    var i;
    var out = "";
    for (i = 0; i < b.length; i++) out += String.fromCharCode(b[i]);
    try {
      return decodeURIComponent(escape(out));
    } catch (err) {
      return out;
    }
  };
  Pb.prototype.skip = function (wt) {
    if (wt === 0) this.u();
    else if (wt === 1) this.i += 8;
    else if (wt === 2) this.i += this.u();
    else if (wt === 5) this.i += 4;
  };

  function zig(n) {
    return (n >>> 1) ^ -(n & 1);
  }

  function packedU(bytes) {
    var p = new Pb(bytes);
    var out = [];
    while (p.i < p.n) out.push(p.u());
    return out;
  }

  function decodeValue(bytes) {
    var p = new Pb(bytes);
    var v = "";
    while (p.i < p.n) {
      var k = p.u();
      var fn = k >> 3;
      var wt = k & 7;
      if (fn === 1 && wt === 2) v = p.str();
      else if (fn === 7 && wt === 0) v = p.u() ? "true" : "false";
      else if (wt === 0) v = String(p.u());
      else p.skip(wt);
    }
    return v;
  }

  function decodeGeom(cmds, extent, size) {
    var x = 0;
    var y = 0;
    var i = 0;
    var scale = size / (extent || 4096);
    var rings = [];
    var ring = [];
    while (i < cmds.length) {
      var c = cmds[i++];
      var cmd = c & 7;
      var count = c >>> 3;
      var k;
      if (cmd === 1 || cmd === 2) {
        for (k = 0; k < count && i + 1 < cmds.length; k++) {
          x += zig(cmds[i++]);
          y += zig(cmds[i++]);
          if (cmd === 1) {
            if (ring.length >= 4) rings.push(ring);
            ring = [];
          }
          ring.push(x * scale, y * scale);
        }
      } else if (cmd === 7) {
        if (ring.length >= 4) {
          ring.push(ring[0], ring[1]);
          rings.push(ring);
          ring = [];
        }
      }
    }
    if (ring.length >= 4) rings.push(ring);
    return rings;
  }

  function decodeFeature(bytes, extent, size) {
    var p = new Pb(bytes);
    var type = 0;
    var tags = [];
    var geom = [];
    while (p.i < p.n) {
      var k = p.u();
      var fn = k >> 3;
      var wt = k & 7;
      if (fn === 2 && wt === 2) tags = packedU(p.bytes());
      else if (fn === 2 && wt === 0) tags.push(p.u());
      else if (fn === 3 && wt === 0) type = p.u();
      else if (fn === 4 && wt === 2) geom = packedU(p.bytes());
      else if (fn === 4 && wt === 0) geom.push(p.u());
      else p.skip(wt);
    }
    return { type: type, tags: tags, rings: decodeGeom(geom, extent, size) };
  }

  function propsFrom(tags, keys, values) {
    var out = {};
    var i;
    for (i = 0; i + 1 < tags.length; i += 2) {
      var key = keys[tags[i]];
      if (key) out[key] = values[tags[i + 1]] || "";
    }
    return out;
  }

  function decodeLayer(bytes, size) {
    var p = new Pb(bytes);
    var name = "";
    var extent = 4096;
    var keys = [];
    var values = [];
    var feats = [];
    while (p.i < p.n) {
      var k = p.u();
      var fn = k >> 3;
      var wt = k & 7;
      if (fn === 1 && wt === 2) name = p.str();
      else if (fn === 2 && wt === 2) feats.push(p.bytes());
      else if (fn === 3 && wt === 2) keys.push(p.str());
      else if (fn === 4 && wt === 2) values.push(decodeValue(p.bytes()));
      else if (fn === 5 && wt === 0) extent = p.u();
      else p.skip(wt);
    }
    return {
      name: name,
      features: feats.map(function (raw) {
        var f = decodeFeature(raw, extent, size);
        f.props = propsFrom(f.tags, keys, values);
        return f;
      })
    };
  }

  function decodeMvt(bytes, size) {
    var p = new Pb(bytes);
    var layers = {};
    while (p.i < p.n) {
      var k = p.u();
      var fn = k >> 3;
      var wt = k & 7;
      if (fn === 3 && wt === 2) {
        var layer = decodeLayer(p.bytes(), size);
        if (layer.name) layers[layer.name] = layer.features;
      } else {
        p.skip(wt);
      }
    }
    return layers;
  }

  function strokeRings(ctx, rings) {
    var i;
    var j;
    ctx.beginPath();
    for (i = 0; i < rings.length; i++) {
      var r = rings[i];
      if (r.length < 4) continue;
      ctx.moveTo(r[0], r[1]);
      for (j = 2; j < r.length; j += 2) ctx.lineTo(r[j], r[j + 1]);
    }
    ctx.stroke();
  }

  function fillRings(ctx, rings) {
    var i;
    var j;
    ctx.beginPath();
    for (i = 0; i < rings.length; i++) {
      var r = rings[i];
      if (r.length < 6) continue;
      ctx.moveTo(r[0], r[1]);
      for (j = 2; j < r.length; j += 2) ctx.lineTo(r[j], r[j + 1]);
      ctx.closePath();
    }
    try {
      ctx.fill("evenodd");
    } catch (err) {
      ctx.fill();
    }
  }

  function roadWidth(hw) {
    if (hw === "motorway" || hw === "trunk") return 3.4;
    if (hw === "primary" || hw === "motorway_link" || hw === "trunk_link") return 2.6;
    if (hw === "secondary" || hw === "primary_link") return 2.1;
    if (hw === "tertiary" || hw === "residential" || hw === "unclassified") return 1.5;
    return 1.05;
  }

  function paintMvt(ctx, bytes, size) {
    var layers = decodeMvt(bytes, size);
    var water = layers.water || [];
    var road = layers.road || [];
    var i;
    ctx.fillStyle = "rgba(42, 88, 118, 0.58)";
    for (i = 0; i < water.length; i++) {
      if (water[i].type === 3) fillRings(ctx, water[i].rings);
    }
    ctx.lineJoin = "round";
    ctx.lineCap = "round";
    ctx.strokeStyle = "rgba(214, 210, 198, 0.94)";
    for (i = 0; i < road.length; i++) {
      if (road[i].type !== 2 && road[i].type !== 3) continue;
      ctx.lineWidth = roadWidth(road[i].props.highway);
      strokeRings(ctx, road[i].rings);
    }
  }

  function gunzip(u8) {
    if (!u8 || u8.length < 2 || u8[0] !== 0x1f || u8[1] !== 0x8b) {
      return Promise.resolve(u8);
    }
    if (typeof DecompressionStream === "undefined") return Promise.resolve(u8);
    return new Response(new Blob([u8]).stream().pipeThrough(new DecompressionStream("gzip")))
      .arrayBuffer()
      .then(function (buf) {
        return new Uint8Array(buf);
      });
  }

  function PMTilesImagery(pm, header) {
    this._pm = pm;
    this.tilingScheme = new Cesium.WebMercatorTilingScheme();
    this.rectangle = Cesium.Rectangle.fromDegrees(
      header.minLon,
      header.minLat,
      header.maxLon,
      header.maxLat
    );
    this.tileWidth = 256;
    this.tileHeight = 256;
    this.minimumLevel = header.minZoom;
    this.maximumLevel = header.maxZoom;
    this.hasAlphaChannel = true;
    this.credit = new Cesium.Credit("USGS NAIP, build-time only", false);
    this.errorEvent = new Cesium.Event();
    this.ready = true;
    this.readyPromise = Promise.resolve(true);
  }
  PMTilesImagery.prototype.getTileCredits = function () {
    return [];
  };
  PMTilesImagery.prototype.requestImage = function (x, y, level) {
    return this._pm.getZxy(level, x, y).then(function (entry) {
      if (!entry || !entry.data) return emptyTile();
      var blob = new Blob([entry.data], { type: "image/jpeg" });
      var url = URL.createObjectURL(blob);
      return Cesium.Resource.fetchImage({ url: url }).then(
        function (img) {
          URL.revokeObjectURL(url);
          return img;
        },
        function () {
          URL.revokeObjectURL(url);
          return emptyTile();
        }
      );
    }).catch(function () {
      return emptyTile();
    });
  };

  function PMTilesMVT(pm, header) {
    this._pm = pm;
    this.tilingScheme = new Cesium.WebMercatorTilingScheme();
    this.rectangle = Cesium.Rectangle.fromDegrees(
      header.minLon,
      header.minLat,
      header.maxLon,
      header.maxLat
    );
    this.tileWidth = 256;
    this.tileHeight = 256;
    this.minimumLevel = header.minZoom;
    this.maximumLevel = header.maxZoom;
    this.hasAlphaChannel = true;
    this.credit = new Cesium.Credit("OpenStreetMap contributors", false);
    this.errorEvent = new Cesium.Event();
    this.ready = true;
    this.readyPromise = Promise.resolve(true);
  }
  PMTilesMVT.prototype.getTileCredits = function () {
    return [];
  };
  PMTilesMVT.prototype.requestImage = function (x, y, level) {
    return this._pm.getZxy(level, x, y).then(function (entry) {
      var canvas = emptyTile();
      if (!entry || !entry.data) return canvas;
      var raw = entry.data instanceof Uint8Array ? entry.data : new Uint8Array(entry.data);
      return gunzip(raw).then(function (bytes) {
        paintMvt(canvas.getContext("2d"), bytes, 256);
        return canvas;
      });
    }).catch(function () {
      return emptyTile();
    });
  };

  function sampleDem(lon, lat) {
    if (!demGrid) return 0;
    var fx = (lon - demGrid.west) / (demGrid.east - demGrid.west);
    var fy = (lat - demGrid.south) / (demGrid.north - demGrid.south);
    if (fx < 0 || fy < 0 || fx > 1 || fy > 1) return 0;
    var c = fx * (demGrid.cols - 1);
    var r = fy * (demGrid.rows - 1);
    var c0 = Math.floor(c);
    var r0 = Math.floor(r);
    var c1 = Math.min(c0 + 1, demGrid.cols - 1);
    var r1 = Math.min(r0 + 1, demGrid.rows - 1);
    var tx = c - c0;
    var ty = r - r0;
    var h00 = demGrid.heights[r0][c0];
    var h10 = demGrid.heights[r0][c1];
    var h01 = demGrid.heights[r1][c0];
    var h11 = demGrid.heights[r1][c1];
    return (h00 * (1 - tx) + h10 * tx) * (1 - ty) + (h01 * (1 - tx) + h11 * tx) * ty;
  }

  function loadDem(url) {
    if (!url) {
      demGrid = null;
      lastDem = "";
      viewer.terrainProvider = new Cesium.EllipsoidTerrainProvider();
      return Promise.resolve(false);
    }
    if (url === lastDem && demGrid) return Promise.resolve(true);
    return xhr(url, "text")
      .then(function (text) { return JSON.parse(text); })
      .then(function (json) {
        demGrid = {
          west: json.west,
          south: json.south,
          east: json.east,
          north: json.north,
          cols: (json.heights[0] || []).length,
          rows: json.heights.length,
          heights: json.heights
        };
        lastDem = url;
        var tile = 32;
        var scheme = new Cesium.GeographicTilingScheme({
          rectangle: Cesium.Rectangle.fromDegrees(
            json.west, json.south, json.east, json.north
          ),
          numberOfLevelZeroTilesX: 1,
          numberOfLevelZeroTilesY: 1
        });
        viewer.terrainProvider = new Cesium.CustomHeightmapTerrainProvider({
          width: tile,
          height: tile,
          callback: function (x, y, level) {
            var rect = scheme.tileXYToRectangle(x, y, level);
            var buf = new Float32Array(tile * tile);
            var i = 0;
            for (var row = 0; row < tile; row++) {
              var lat = Cesium.Math.toDegrees(
                rect.north + (rect.south - rect.north) * (row + 0.5) / tile
              );
              for (var col = 0; col < tile; col++) {
                var lon = Cesium.Math.toDegrees(
                  rect.west + (rect.east - rect.west) * (col + 0.5) / tile
                );
                buf[i++] = sampleDem(lon, lat);
              }
            }
            return buf;
          },
          tilingScheme: new Cesium.GeographicTilingScheme({
            rectangle: Cesium.Rectangle.fromDegrees(
              json.west, json.south, json.east, json.north
            ),
            numberOfLevelZeroTilesX: 1,
            numberOfLevelZeroTilesY: 1
          })
        });
        return true;
      })
      .catch(function () {
        demGrid = null;
        lastDem = url || "";
        viewer.terrainProvider = new Cesium.EllipsoidTerrainProvider();
        return false;
      });
  }

  function ShadeTile(img, bbox) {
    var w = img.naturalWidth || img.width || 256;
    var h = img.naturalHeight || img.height || 256;
    this._img = img;
    this.rectangle = Cesium.Rectangle.fromDegrees(bbox.west, bbox.south, bbox.east, bbox.north);
    this.tilingScheme = new Cesium.GeographicTilingScheme({
      rectangle: this.rectangle,
      numberOfLevelZeroTilesX: 1,
      numberOfLevelZeroTilesY: 1
    });
    this.tileWidth = w;
    this.tileHeight = h;
    this.minimumLevel = 0;
    this.maximumLevel = 0;
    this.hasAlphaChannel = false;
    this.credit = new Cesium.Credit("pack hillshade", false);
    this.errorEvent = new Cesium.Event();
    this.ready = true;
    this.readyPromise = Promise.resolve(true);
  }
  ShadeTile.prototype.getTileCredits = function () {
    return [];
  };
  ShadeTile.prototype.requestImage = function () {
    return Promise.resolve(this._img);
  };

  function loadShade(url, bbox) {
    if (!url || !bbox) {
      if (shadeLayer) {
        viewer.imageryLayers.remove(shadeLayer, true);
        shadeLayer = null;
      }
      lastShade = "";
      return Promise.resolve(false);
    }
    if (url === lastShade && shadeLayer) {
      shadeLayer.show = true;
      return Promise.resolve(true);
    }
    if (url === lastShade && !shadeLayer) return Promise.resolve(false);
    if (shadeLayer) {
      viewer.imageryLayers.remove(shadeLayer, true);
      shadeLayer = null;
    }
    lastShade = url;
    return xhrImage(url)
      .then(function (img) {
        shadeLayer = viewer.imageryLayers.addImageryProvider(new ShadeTile(img, bbox), 0);
        shadeLayer.show = true;
        viewer.scene.requestRender();
        return true;
      })
      .catch(function () {
        return false;
      });
  }

  function loadOsm(url, on) {
    if (osmLayer && url === lastOsm) {
      osmLayer.show = !!on;
      viewer.scene.requestRender();
      return Promise.resolve(true);
    }
    if (!on || !url) {
      if (osmLayer) osmLayer.show = false;
      if (!url) {
        lastOsm = "";
        if (osmLayer) {
          viewer.imageryLayers.remove(osmLayer, true);
          osmLayer = null;
        }
      }
      return Promise.resolve(false);
    }
    if (url === lastOsm && !osmLayer) return Promise.resolve(false);
    if (osmLayer) {
      viewer.imageryLayers.remove(osmLayer, true);
      osmLayer = null;
    }
    lastOsm = url;
    return xhr(url, "arraybuffer")
      .then(function (buf) {
        var pm = new pmtiles.PMTiles(new BufferSource(url, buf));
        return pm.getHeader().then(function (header) {
          osmLayer = viewer.imageryLayers.addImageryProvider(new PMTilesMVT(pm, header), 1);
          osmLayer.show = true;
          viewer.scene.requestRender();
          return true;
        });
      })
      .catch(function () {
        return false;
      });
  }

  function loadAerial(url, on) {
    if (aerialLayer && url === lastAerial) {
      aerialLayer.show = !!on;
      viewer.scene.requestRender();
      return Promise.resolve(true);
    }
    if (!on || !url) {
      if (aerialLayer) aerialLayer.show = false;
      if (!url) {
        lastAerial = "";
        if (aerialLayer) {
          viewer.imageryLayers.remove(aerialLayer, true);
          aerialLayer = null;
        }
      }
      return Promise.resolve(false);
    }
    if (url === lastAerial && !aerialLayer) return Promise.resolve(false);
    if (aerialLayer) {
      viewer.imageryLayers.remove(aerialLayer, true);
      aerialLayer = null;
    }
    lastAerial = url;
    return xhr(url, "arraybuffer")
      .then(function (buf) {
        var pm = new pmtiles.PMTiles(new BufferSource(url, buf));
        return pm.getHeader().then(function (header) {
          aerialLayer = viewer.imageryLayers.addImageryProvider(new PMTilesImagery(pm, header), 2);
          aerialLayer.show = true;
          viewer.scene.requestRender();
          return true;
        });
      })
      .catch(function () {
        return false;
      });
  }

  function loadGeo(url, color, width, existing, slot) {
    var key = url || "";
    if (key === (slot === "water" ? lastWater : lastContours)) {
      return Promise.resolve(existing);
    }
    if (existing) {
      viewer.dataSources.remove(existing, true);
    }
    if (slot === "water") {
      lastWater = key;
      waterSource = null;
    } else {
      lastContours = key;
      contourSource = null;
    }
    if (!url) return Promise.resolve(null);
    return xhr(url, "text")
      .then(function (text) {
        return Cesium.GeoJsonDataSource.load(JSON.parse(text), {
          stroke: color,
          fill: color.withAlpha(0.28),
          strokeWidth: width || 2,
          clampToGround: true
        });
      })
      .then(function (ds) {
        ds.entities.values.forEach(function (ent) {
          if (ent.polygon) {
            ent.polygon.material = color.withAlpha(0.28);
            ent.polygon.outline = true;
            ent.polygon.outlineColor = color;
          }
          if (ent.polyline) {
            ent.polyline.material = color;
            ent.polyline.width = width || 2;
            ent.polyline.clampToGround = true;
          }
        });
        viewer.dataSources.add(ds);
        return ds;
      })
      .catch(function () { return null; });
  }

  function clearCoins() {
    var drop = [];
    viewer.entities.values.forEach(function (ent) {
      var id = String(ent.id || "");
      if (id.indexOf("coin:") === 0 || id.indexOf("trail:") === 0 || id.indexOf("ring:") === 0 || id === "puck" || id === "route" || id === "dest" || id === "held" || id === "pack-box") {
        drop.push(ent);
      }
    });
    drop.forEach(function (ent) { viewer.entities.remove(ent); });
  }

  function drawPackBox(spec) {
    var b = spec.bbox;
    if (!b) return;
    viewer.entities.add({
      id: "pack-box",
      polyline: {
        positions: Cesium.Cartesian3.fromDegreesArray([
          b.west, b.south, b.east, b.south, b.east, b.north, b.west, b.north, b.west, b.south
        ]),
        width: 1.5,
        material: Cesium.Color.fromCssColorString("#B8BDC2").withAlpha(0.55),
        clampToGround: true
      }
    });
  }

  function drawPuck(spec) {
    var p = spec.puck;
    if (!p || !p.show) return;
    var heading = Cesium.Math.toRadians(p.heading == null ? 0 : p.heading);
    viewer.entities.add({
      id: "puck",
      name: "YOU",
      position: cart(p.lat, p.lon, 4),
      orientation: Cesium.Transforms.headingPitchRollQuaternion(
        cart(p.lat, p.lon, 4),
        new Cesium.HeadingPitchRoll(heading, 0, 0)
      ),
      ellipse: {
        semiMajorAxis: 14,
        semiMinorAxis: 14,
        material: Cesium.Color.WHITE.withAlpha(0.92),
        outline: true,
        outlineColor: Cesium.Color.BLACK,
        height: 2
      },
      point: {
        pixelSize: 11,
        color: Cesium.Color.WHITE,
        outlineColor: Cesium.Color.BLACK,
        outlineWidth: 2,
        disableDepthTestDistance: Number.POSITIVE_INFINITY
      }
    });
  }

  function drawCoins(spec) {
    var layers = spec.layers || [];
    var partyOn = layers.indexOf("party") >= 0;
    var marksOn = layers.indexOf("marks") >= 0;
    (spec.pips || []).forEach(function (pip) {
      var isMark = !!pip.markKind;
      if (isMark && !marksOn) return;
      if (!isMark && !partyOn) return;
      var size = pip.lead ? 16 : 12;
      if (pip.kid) size += 2;
      var label = ((pip.ageTitle || "") + " " + (pip.ageLabel || "")).trim();
      if (pip.markKind) label = pip.markKind + (label ? " · " + label : "");
      viewer.entities.add({
        id: "coin:" + pip.id,
        name: pip.id,
        position: cart(pip.lat, pip.lon, 6),
        point: {
          pixelSize: size,
          color: colorFor(pip.condition, pip.ghost),
          outlineColor: pip.kid ? Cesium.Color.WHITE : Cesium.Color.BLACK,
          outlineWidth: pip.kid ? 3 : 1,
          disableDepthTestDistance: Number.POSITIVE_INFINITY
        },
        label: label
          ? {
              text: label,
              font: "11px monospace",
              fillColor: Cesium.Color.WHITE,
              outlineColor: Cesium.Color.BLACK,
              outlineWidth: 3,
              style: Cesium.LabelStyle.FILL_AND_OUTLINE,
              pixelOffset: new Cesium.Cartesian2(0, -18),
              disableDepthTestDistance: Number.POSITIVE_INFINITY
            }
          : undefined,
        ellipse: pip.rangeMeters
          ? {
              semiMajorAxis: pip.rangeMeters,
              semiMinorAxis: pip.rangeMeters,
              material: Cesium.Color.fromCssColorString("#B8BDC2").withAlpha(0.12),
              outline: true,
              outlineColor: Cesium.Color.fromCssColorString("#B8BDC2").withAlpha(0.7),
              height: 1
            }
          : undefined
      });
    });
  }

  function drawRoute(spec) {
    var route = spec.route || [];
    if (route.length >= 2) {
      var flat = [];
      route.forEach(function (pt) {
        flat.push(pt[1], pt[0]);
      });
      viewer.entities.add({
        id: "route",
        polyline: {
          positions: Cesium.Cartesian3.fromDegreesArray(flat),
          width: spec.travel === "walk" ? 3 : 5,
          material: Cesium.Color.fromCssColorString("#E10600"),
          clampToGround: true
        }
      });
    }
    if (spec.dest) {
      viewer.entities.add({
        id: "dest",
        position: cart(spec.dest[0], spec.dest[1], 8),
        point: {
          pixelSize: 10,
          color: Cesium.Color.fromCssColorString("#ED510A"),
          outlineColor: Cesium.Color.WHITE,
          outlineWidth: 1,
          disableDepthTestDistance: Number.POSITIVE_INFINITY
        }
      });
    }
    if (spec.held) {
      viewer.entities.add({
        id: "held",
        position: cart(spec.held[0], spec.held[1], 8),
        point: {
          pixelSize: 9,
          color: Cesium.Color.WHITE,
          outlineColor: Cesium.Color.fromCssColorString("#E10600"),
          outlineWidth: 2,
          disableDepthTestDistance: Number.POSITIVE_INFINITY
        }
      });
    }
    (spec.trails || []).forEach(function (seg, i) {
      if (!seg || seg.length < 2) return;
      var flat = [];
      seg.forEach(function (pt) { flat.push(pt[1], pt[0]); });
      viewer.entities.add({
        id: "trail:" + i,
        polyline: {
          positions: Cesium.Cartesian3.fromDegreesArray(flat),
          width: 2,
          material: Cesium.Color.fromCssColorString("#B8BDC2").withAlpha(0.7),
          clampToGround: true
        }
      });
    });
    (spec.rings || []).forEach(function (ring, i) {
      viewer.entities.add({
        id: "ring:" + i,
        position: cart(ring.lat, ring.lon, 2),
        ellipse: {
          semiMajorAxis: ring.meters,
          semiMinorAxis: ring.meters,
          material: Cesium.Color.TRANSPARENT,
          outline: true,
          outlineColor: ring.overdue
            ? Cesium.Color.fromCssColorString("#E10600")
            : Cesium.Color.fromCssColorString("#B8BDC2"),
          height: 2
        }
      });
    });
  }

  function paintLayer(layer, spec) {
    if (!layer) return;
    layer.saturation = spec.palette === "packIR" ? 0.05 : 1.05;
    layer.contrast = spec.palette === "packIR" ? 1.35 : spec.lamp === "sun" ? 1.15 : 1.02;
    layer.brightness = spec.lamp === "sun" ? 1.14 : spec.lamp === "night" ? 0.78 : 1.0;
    layer.gamma = spec.palette === "nvg" ? 0.85 : 1.0;
    layer.hue = spec.palette === "nvg" ? 2.1 : 0.0;
  }

  function applyPalette(spec) {
    var look = (spec.lamp || "") + "|" + (spec.palette || "");
    if (look === lastLook) return;
    lastLook = look;
    var globe = viewer.scene.globe;
    globe.baseColor = Cesium.Color.fromCssColorString(GROUND);
    globe.showGroundAtmosphere = false;
    globe.enableLighting = spec.lamp === "sun";
    paintLayer(shadeLayer, spec);
    paintLayer(osmLayer, spec);
    paintLayer(aerialLayer, spec);
    if (spec.palette === "nvg") {
      globe.baseColor = Cesium.Color.fromCssColorString("#031a08");
    }
    if (spec.lamp === "night") {
      viewer.scene.light = new Cesium.DirectionalLight({
        direction: new Cesium.Cartesian3(0.2, 0.3, -1),
        intensity: 0.35,
        color: Cesium.Color.fromCssColorString("#ff2a14")
      });
    } else if (spec.lamp === "sun") {
      viewer.scene.light = new Cesium.DirectionalLight({
        direction: new Cesium.Cartesian3(0, -0.4, -1),
        intensity: 2.2,
        color: Cesium.Color.WHITE
      });
    } else {
      viewer.scene.light = new Cesium.DirectionalLight({
        direction: new Cesium.Cartesian3(0.15, -0.5, -1),
        intensity: 1.1,
        color: Cesium.Color.WHITE
      });
    }
  }

  function cameraFor(spec) {
    var puck = spec.puck || spec.home || { lat: 31.76, lon: -106.49 };
    var height = spec.height || 900;
    var pitch = spec.pitch == null ? -90 : spec.pitch;
    var heading = spec.heading == null ? 0 : spec.heading;
    if (spec.godsEye) {
      viewer.trackedEntity = undefined;
      viewer.clock.shouldAnimate = false;
      var pts = [];
      if (spec.puck && spec.puck.show) pts.push(cart(spec.puck.lat, spec.puck.lon));
      (spec.pips || []).forEach(function (p) { pts.push(cart(p.lat, p.lon)); });
      (spec.frameExtra || []).forEach(function (p) { pts.push(cart(p[0], p[1])); });
      if (!pts.length) pts.push(cart(puck.lat, puck.lon));
      var sphere = Cesium.BoundingSphere.fromPoints(pts);
      var range = spec.range || Math.max(sphere.radius * 1.15, 160);
      viewer.camera.flyToBoundingSphere(sphere, {
        duration: spec.fitToken === lastFit ? 0 : (spec.fly || 2),
        offset: new Cesium.HeadingPitchRange(
          Cesium.Math.toRadians(heading),
          Cesium.Math.toRadians(pitch),
          range
        )
      });
      lastFit = spec.fitToken;
      return;
    }
    if (spec.lockOn || spec.followId) {
      var trackId = spec.followId ? "coin:" + spec.followId : "puck";
      var tracked = viewer.entities.getById(trackId);
      if (!tracked) tracked = viewer.entities.getById("puck");
      viewer.trackedEntity = tracked || undefined;
      viewer.clock.shouldAnimate = true;
      return;
    }
    viewer.trackedEntity = undefined;
    viewer.clock.shouldAnimate = false;
    if (spec.fitToken !== lastFit) {
      viewer.camera.setView({
        destination: Cesium.Cartesian3.fromDegrees(puck.lon, puck.lat, height),
        orientation: {
          heading: 0,
          pitch: Cesium.Math.toRadians(-90),
          roll: 0
        }
      });
      lastFit = spec.fitToken;
    }
  }

  function pickId(position) {
    var picked = viewer.scene.pick(position);
    if (!Cesium.defined(picked) || !picked.id) return null;
    var ent = picked.id;
    var id = String(ent.id || ent);
    if (id.indexOf("coin:") === 0) return id.slice(5);
    if (id === "puck") return "YOU";
    return null;
  }

  function lonlat(position) {
    var ray = viewer.camera.getPickRay(position);
    var carto = viewer.scene.globe.pick(ray, viewer.scene);
    if (!carto) return null;
    var c = Cesium.Cartographic.fromCartesian(carto);
    return { lat: Cesium.Math.toDegrees(c.latitude), lon: Cesium.Math.toDegrees(c.longitude) };
  }

  function bindInput() {
    var el = viewer.canvas;
    el.addEventListener("pointerdown", function (ev) {
      var pos = new Cesium.Cartesian2(ev.offsetX, ev.offsetY);
      holdStart = pos;
      pressedId = pickId(pos);
      holdTimer = setTimeout(function () {
        var ll = lonlat(pos);
        if (!ll) return;
        if (pressedId) post({ type: "personHold", id: pressedId, lat: ll.lat, lon: ll.lon });
        else post({ type: "hold", lat: ll.lat, lon: ll.lon });
      }, 400);
    });
    el.addEventListener("pointerup", function (ev) {
      if (holdTimer) clearTimeout(holdTimer);
      holdTimer = null;
      var pos = new Cesium.Cartesian2(ev.offsetX, ev.offsetY);
      var ll = lonlat(pos);
      if (!ll) return;
      var now = Date.now();
      var id = pickId(pos);
      if (lastTapAt && now - lastTapAt < 320 && lastTapPos) {
        lastTapAt = 0;
        if (id) post({ type: "personDoubleTap", id: id, lat: ll.lat, lon: ll.lon });
        else post({ type: "emptyDoubleTap", lat: ll.lat, lon: ll.lon });
        return;
      }
      lastTapAt = now;
      lastTapPos = pos;
      if (id) post({ type: "personTap", id: id, lat: ll.lat, lon: ll.lon });
      else post({ type: "tap", lat: ll.lat, lon: ll.lon });
    });
    el.addEventListener("pointercancel", function () {
      if (holdTimer) clearTimeout(holdTimer);
      holdTimer = null;
    });
  }

  function apply(spec) {
    if (!viewer) {
      pending = spec;
      return;
    }
    var layers = spec.layers || [];
    var aerialOn = layers.indexOf("aerial") >= 0 && spec.ground !== "streets";
    var streetsOn = spec.ground !== "aerial";
    var waterOn = layers.indexOf("water") >= 0;
    var vectorsOn = layers.indexOf("vectors") >= 0 || layers.indexOf("shade") >= 0;
    var shadeUrl = spec.shadeUrl || packAsset(spec, "hillshade.png");
    var osmUrl = spec.osmUrl || packAsset(spec, "osm.pmtiles");
    clearCoins();
    drawPackBox(spec);
    drawPuck(spec);
    drawCoins(spec);
    drawRoute(spec);
    applyPalette(spec);
    cameraFor(spec);
    viewer.scene.requestRender();
    post({ type: "pulse" });
    var groundKey = [
      spec.packId || "",
      shadeUrl,
      osmUrl,
      spec.aerialUrl || "",
      spec.demUrl || "",
      spec.waterUrl || "",
      spec.contoursUrl || "",
      streetsOn ? "1" : "0",
      aerialOn ? "1" : "0",
      waterOn ? "1" : "0",
      vectorsOn ? "1" : "0",
      spec.ground || "",
      spec.bbox
        ? [spec.bbox.west, spec.bbox.south, spec.bbox.east, spec.bbox.north].join(",")
        : ""
    ].join("|");
    if (groundKey === lastGroundKey) return;
    lastGroundKey = groundKey;
    loadDem(spec.demUrl).then(function () { viewer.scene.requestRender(); });
    loadShade(shadeUrl, spec.bbox)
      .then(function () { return loadOsm(osmUrl, streetsOn); })
      .then(function () { return loadAerial(spec.aerialUrl, aerialOn); });
    loadGeo(
      waterOn ? spec.waterUrl : "",
      Cesium.Color.fromCssColorString("#3FA7C9"),
      2,
      waterSource,
      "water"
    ).then(function (ds) { waterSource = ds; });
    loadGeo(
      vectorsOn ? spec.contoursUrl : "",
      Cesium.Color.fromCssColorString("#B8BDC2"),
      1.25,
      contourSource,
      "contours"
    ).then(function (ds) { contourSource = ds; });
  }

  function boot() {
    blockIon();
    viewer = new Cesium.Viewer("globe", {
      baseLayer: false,
      terrainProvider: new Cesium.EllipsoidTerrainProvider(),
      skyBox: false,
      skyAtmosphere: false,
      geocoder: false,
      homeButton: false,
      sceneModePicker: false,
      baseLayerPicker: false,
      navigationHelpButton: false,
      animation: false,
      timeline: false,
      fullscreenButton: false,
      vrButton: false,
      infoBox: false,
      selectionIndicator: false,
      creditContainer: document.createElement("div"),
      requestRenderMode: true,
      maximumRenderTimeChange: Infinity,
      showRenderLoopErrors: false,
      contextOptions: { webgl: { alpha: false } }
    });
    viewer.scene.globe.baseColor = Cesium.Color.fromCssColorString(GROUND);
    viewer.scene.globe.showGroundAtmosphere = false;
    viewer.scene.moon = undefined;
    viewer.scene.sun = undefined;
    viewer.scene.fog.enabled = false;
    viewer.scene.backgroundColor = Cesium.Color.BLACK;
    viewer.clock.shouldAnimate = false;
    viewer.scene.globe.tileLoadProgressEvent.addEventListener(function () {
      viewer.scene.requestRender();
    });
    bindInput();
    window.KHAN.viewer = viewer;
    if (pending) {
      var spec = pending;
      pending = null;
      apply(spec);
    }
  }

  window.KHAN = {
    apply: apply,
    viewer: null
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
