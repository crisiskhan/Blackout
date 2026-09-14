/* KHAN EYE desk. file:// Cesium only. No ion. No live feeds. */
(function () {
  "use strict";

  var pending = null;
  var viewer = null;
  var lastFit = -1;
  var lastAerial = "";
  var lastDem = "";
  var aerialLayer = null;
  var waterSource = null;
  var contourSource = null;
  var holdTimer = null;
  var holdStart = null;
  var lastTapAt = 0;
  var lastTapPos = null;
  var pressedId = null;
  var demGrid = null;

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
    this.hasAlphaChannel = false;
    this.credit = new Cesium.Credit("USGS NAIP, build-time only", false);
    this.errorEvent = new Cesium.Event();
    this.ready = true;
    this.readyPromise = Promise.resolve(true);
  }
  PMTilesImagery.prototype.getTileCredits = function () {
    return [];
  };
  PMTilesImagery.prototype.requestImage = function (x, y, level) {
    var self = this;
    return this._pm.getZxy(level, x, y).then(function (entry) {
      if (!entry) return undefined;
      var blob = new Blob([entry.data], { type: "image/jpeg" });
      var url = URL.createObjectURL(blob);
      return Cesium.Resource.fetchImage({ url: url }).then(
        function (img) {
          URL.revokeObjectURL(url);
          return img;
        },
        function () {
          URL.revokeObjectURL(url);
          return undefined;
        }
      );
    }).catch(function () {
      return undefined;
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
      viewer.terrainProvider = new Cesium.EllipsoidTerrainProvider();
      return Promise.resolve(false);
    }
    if (url === lastDem && demGrid) return Promise.resolve(true);
    return fetch(url)
      .then(function (res) { return res.json(); })
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
        lastDem = "";
        viewer.terrainProvider = new Cesium.EllipsoidTerrainProvider();
        return false;
      });
  }

  function loadAerial(url, on) {
    if (aerialLayer) {
      viewer.imageryLayers.remove(aerialLayer, true);
      aerialLayer = null;
    }
    if (!on || !url) {
      lastAerial = "";
      return Promise.resolve(false);
    }
    return fetch(url)
      .then(function (res) { return res.arrayBuffer(); })
      .then(function (buf) {
        var pm = new pmtiles.PMTiles(new BufferSource(url, buf));
        return pm.getHeader().then(function (header) {
          aerialLayer = viewer.imageryLayers.addImageryProvider(new PMTilesImagery(pm, header));
          lastAerial = url;
          return true;
        });
      })
      .catch(function () {
        lastAerial = "";
        return false;
      });
  }

  function loadGeo(url, color, width, existing) {
    if (existing) {
      viewer.dataSources.remove(existing, true);
    }
    if (!url) return Promise.resolve(null);
    return Cesium.GeoJsonDataSource.load(url, {
      stroke: color,
      fill: color.withAlpha(0.28),
      strokeWidth: width || 2,
      clampToGround: true
    }).then(function (ds) {
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
    }).catch(function () { return null; });
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

  function applyPalette(spec) {
    var globe = viewer.scene.globe;
    globe.baseColor = Cesium.Color.fromCssColorString("#141414");
    globe.showGroundAtmosphere = false;
    globe.enableLighting = spec.lamp === "sun";
    var layer = aerialLayer;
    if (layer) {
      layer.saturation = spec.palette === "packIR" ? 0.05 : 1.2;
      layer.contrast = spec.palette === "packIR" ? 1.35 : spec.lamp === "sun" ? 1.2 : 1.05;
      layer.brightness = spec.lamp === "sun" ? 1.18 : spec.lamp === "night" ? 0.72 : 1.0;
      layer.gamma = spec.palette === "nvg" ? 0.85 : 1.0;
      layer.hue = spec.palette === "nvg" ? 2.1 : 0.0;
    }
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
      var target = puck;
      if (spec.followId) {
        var hit = (spec.pips || []).filter(function (p) { return p.id === spec.followId; })[0];
        if (hit) target = hit;
      }
      viewer.camera.setView({
        destination: Cesium.Cartesian3.fromDegrees(target.lon, target.lat, height),
        orientation: {
          heading: Cesium.Math.toRadians(target.heading || 0),
          pitch: Cesium.Math.toRadians(-90),
          roll: 0
        }
      });
      return;
    }
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
    var cart = viewer.scene.globe.pick(ray, viewer.scene);
    if (!cart) return null;
    var c = Cesium.Cartographic.fromCartesian(cart);
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
    var waterOn = layers.indexOf("water") >= 0;
    var vectorsOn = layers.indexOf("vectors") >= 0 || layers.indexOf("shade") >= 0;
    Promise.resolve()
      .then(function () { return loadDem(spec.demUrl); })
      .then(function () { return loadAerial(spec.aerialUrl, aerialOn); })
      .then(function () {
        return loadGeo(
          waterOn ? spec.waterUrl : "",
          Cesium.Color.fromCssColorString("#3FA7C9"),
          2,
          waterSource
        ).then(function (ds) { waterSource = ds; });
      })
      .then(function () {
        return loadGeo(
          vectorsOn ? spec.contoursUrl : "",
          Cesium.Color.fromCssColorString("#B8BDC2"),
          1.25,
          contourSource
        ).then(function (ds) { contourSource = ds; });
      })
      .then(function () {
        clearCoins();
        drawPackBox(spec);
        drawPuck(spec);
        drawCoins(spec);
        drawRoute(spec);
        applyPalette(spec);
        cameraFor(spec);
        viewer.scene.requestRender();
        post({ type: "pulse" });
      });
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
      contextOptions: { webgl: { alpha: false } }
    });
    viewer.scene.globe.baseColor = Cesium.Color.fromCssColorString("#141414");
    viewer.scene.globe.showGroundAtmosphere = false;
    viewer.scene.moon = undefined;
    viewer.scene.sun = undefined;
    viewer.scene.fog.enabled = false;
    viewer.scene.backgroundColor = Cesium.Color.BLACK;
    viewer.clock.shouldAnimate = false;
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
