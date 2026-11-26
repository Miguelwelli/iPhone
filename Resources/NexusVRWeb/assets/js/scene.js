/* ==========================================================================
   Nexus VR — scene.js
   Three.js engine: 360° skybox, camera rig, stereo VR, floating hub cards,
   portal rings, particles. Exposes NX.scene.
   ========================================================================== */
(function () {
  "use strict";

  var NX = window.NX;
  var U = NX.util;

  var scene = (NX.scene = {
    ready: false,
    renderer: null,
    scene3: null,
    camera: null,
    cameraL: null,
    cameraR: null,
    rig: null,
    sky: null,
    hubGroup: null,
    portalGroup: null,
    particleGroup: null,
    raycaster: null,
    stereo: false,
    quality: "high",
    worldId: "night",
    panoramaCache: {},
    loading: {},
    items: [],
    tween: null
  });

  var THREE = window.THREE;
  // Other modules (games, hands, player) build Three.js objects too.
  NX.THREE = THREE;
  var raycaster;
  var pointerNDC = new (THREE ? THREE.Vector2 : Object)();

  var state = {
    cameraPos: new (THREE ? THREE.Vector3 : Object)(0, 0, 0),
    cameraTarget: new (THREE ? THREE.Vector3 : Object)(0, 0, 0),
    shake: 0,
    flash: 0,
    flashColor: new (THREE ? THREE.Color : Object)(0xffffff),
    hoverScale: 1,
    highlightIndex: -1
  };

  /* --------------------------------------------------------------- helpers */

  function fitPixelRatio() {
    var dpr = window.devicePixelRatio || 1;
    var max = { high: 1.5, medium: 1.25, low: 1.0 }[scene.quality] || 1.5;
    if (!scene.ready) return 1;
    return Math.max(1, Math.min(dpr, max));
  }

  function detectQuality() {
    var q = NX.settings.get("quality");
    if (q && q !== "auto") return q;
    // Heuristic: pixel count + device memory + hardware concurrency
    var px = window.innerWidth * window.innerHeight * (window.devicePixelRatio || 1);
    var mem = navigator.deviceMemory || 4;
    var cores = navigator.hardwareConcurrency || 4;
    var mobile = U.isIOS() || /Android/i.test(navigator.userAgent);
    if (mobile) {
      if (px > 2.6e6 && mem >= 4) return "medium";
      if (px > 1.6e6) return "medium";
      return "low";
    }
    if (px > 3.6e6) return "high";
    if (cores >= 8) return "high";
    return "medium";
  }

  /* --------------------------------------------------------------- init */

  scene.init = function (host) {
    if (scene.ready) return true;
    if (!THREE) {
      NX.bus.emit("fatal", { message: NX.i18n.t("notSupported") });
      return false;
    }
    scene.quality = detectQuality();

    try {
      scene.renderer = new THREE.WebGLRenderer({
        antialias: scene.quality !== "low",
        alpha: false,
        powerPreference: "high-performance",
        stencil: false,
        depth: true
      });
    } catch (e) {
      NX.bus.emit("fatal", { message: NX.i18n.t("webglFail") });
      return false;
    }

    var r = scene.renderer;
    scene.host = host;
    r.setPixelRatio(fitPixelRatio());
    r.setSize(window.innerWidth, window.innerHeight);
    r.outputEncoding = THREE.sRGBEncoding;
    r.toneMapping = THREE.ACESFilmicToneMapping;
    r.toneMappingExposure = 1.0;
    r.autoClear = true;
    r.setClearColor(0x03040a, 1);
    if (r.capabilities && r.capabilities.isWebGL2 === false) {
      scene.quality = "low";
      r.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.2));
    }
    host.appendChild(r.domElement);
    r.domElement.className = "scene-canvas";
    scene.host = host;
    r.domElement.setAttribute("aria-label", "Cena 3D imersiva");

    scene.scene3 = new THREE.Scene();
    scene.scene3.fog = new THREE.FogExp2(0x05060d, 0.02);

    // Panorama dome: a huge sphere viewed from the inside.
    var skyGeo = new THREE.SphereGeometry(60, 64, 40);
    skyGeo.scale(-1, 1, 1);                // inside-out: normals face the viewer
    var skyMat = new THREE.MeshBasicMaterial({
      color: 0xffffff,
      side: THREE.FrontSide,
      depthWrite: false,
      fog: false
    });
    scene.sky = new THREE.Mesh(skyGeo, skyMat);
    scene.sky.renderOrder = -1000;
    scene.sky.matrixAutoUpdate = false;
    scene.scene3.add(scene.sky);

    // Camera
    scene.camera = new THREE.PerspectiveCamera(
      NX.settings.get("fov") || 75,
      window.innerWidth / window.innerHeight,
      0.05,
      200
    );
    scene.camera.rotation.order = "YXZ";

    // Stereo cameras (cloned lazily when VR turns on)
    scene.cameraL = scene.camera.clone();
    scene.cameraR = scene.camera.clone();
    scene.cameraL.name = "L";
    scene.cameraR.name = "R";
    scene.cameraL.rotation.order = "YXZ";
    scene.cameraR.rotation.order = "YXZ";

    raycaster = new THREE.Raycaster();
    raycaster.far = 40;
    scene.raycaster = raycaster;

    // Ambient + subtle directional for the hub objects (panorama is unlit)
    scene.scene3.add(new THREE.AmbientLight(0xa8c4ff, 0.55));
    var key = new THREE.DirectionalLight(0xffffff, 0.65);
    key.position.set(0.6, 1.4, 0.8);
    scene.scene3.add(key);
    var rim = new THREE.PointLight(0x63e8ff, 0.9, 30, 2);
    rim.position.set(-3, 2, 4);
    scene.scene3.add(rim);

    // Hub group holds the floating cards
    scene.hubGroup = new THREE.Group();
    scene.hubGroup.name = "hub";
    scene.scene3.add(scene.hubGroup);

    // Portal rings & particles
    scene.portalGroup = new THREE.Group();
    scene.scene3.add(scene.portalGroup);

    scene.particleGroup = new THREE.Group();
    scene.scene3.add(scene.particleGroup);

    scene.ready = true;
    return true;
  };

  /* ------------------------------------------------------ panorama loading */

  function applySkyTexture(tex, animate) {
    var mat = scene.sky.material;
    mat.map = tex;
    mat.color.set(0xffffff);
    mat.opacity = 1;
    mat.transparent = false;
    mat.needsUpdate = true;
    if (animate) {
      scene.flash = 0.6;
    }
  }

  /**
   * Load a panorama (jpeg) and set it as the skybox; returns a Promise.
   */
  scene.setWorld = function (id, opts) {
    var world = NX.worldById(id);
    var isSame = scene.worldId === id && scene.sky.material.map;
    var changed = scene.worldId !== id;
    scene.worldId = id;
    scene.scene3.fog.color.setHex(world.fog);
    if (changed && scene._particles !== undefined) scene.buildParticles();
    scene.renderer.toneMappingExposure = world.exposure;

    if (scene.panoramaCache[id]) {
      applySkyTexture(scene.panoramaCache[id], !isSame);
      NX.bus.emit("scene:world", world);
      if (isSame) return Promise.resolve(world);
      return Promise.resolve(world);
    }

    var url = (!opts || opts.lq) ? world.lq : world.pano;

    return new Promise(function (resolve) {
      var loader = new THREE.TextureLoader();
      loader.setCrossOrigin("anonymous");

      function load(url, cb) {
        loader.load(url, cb, undefined, function () { cb(null); });
      }

      // progressive: LQ first (fast), then HQ in the background
      load(world.lq, function (tex) {
        if (!tex) {
          load(world.pano, finish);
          return;
        }
        tex.encoding = THREE.sRGBEncoding;
        tex.minFilter = THREE.LinearFilter;
        tex.magFilter = THREE.LinearFilter;
        tex.generateMipmaps = false;
        scene.panoramaCache[id] = tex;
        applySkyTexture(tex, !isSame);
        NX.bus.emit("scene:world", world);
        resolve(world);

        if (scene.quality !== "low") {
          load(world.pano, function (hq) {
            if (!hq) return;
            hq.encoding = THREE.sRGBEncoding;
            hq.minFilter = THREE.LinearMipmapLinearFilter;
            hq.magFilter = THREE.LinearFilter;
            hq.generateMipmaps = true;
            hq.anisotropy = Math.min(4, scene.renderer.capabilities.getMaxAnisotropy());
            if (scene.worldId === id) {
              scene.panoramaCache[id] = hq;
              applySkyTexture(hq, false);
            }
          });
        }
      });

      function finish(tex) {
        if (!tex) {
          NX.bus.emit("toast", { text: "Panorama " + id, kind: "error" });
          resolve(world);
          return;
        }
        tex.encoding = THREE.sRGBEncoding;
        scene.panoramaCache[id] = tex;
        applySkyTexture(tex, !isSame);
        resolve(world);
      }
    });
  };

  /** Preload the low-res panoramas of every world (tiny, used by settings). */
  scene.preloadWorlds = function () {
    NX.worlds.forEach(function (w) {
      if (scene.panoramaCache[w.id]) return;
      var img = new Image();
      img.src = w.lq;
    });
  };

  /* --------------------------------------------------------------- camera */

  scene.updateCamera = function (dt) {
    var inp = NX.input;
    var cam = scene.camera;

    // subtle 6DoF sway (position follows head movement when the device allows it)
    var t = U.now();
    var idle = NX.settings.get("reducedMotion") ? 0 : 1;
    var swayX = Math.sin(t * 0.45) * 0.012 * idle;
    var swayY = Math.cos(t * 0.62) * 0.010 * idle;
    if (state.shake > 0.001) {
      swayX += (Math.random() - 0.5) * state.shake * 0.08;
      swayY += (Math.random() - 0.5) * state.shake * 0.08;
      state.shake *= Math.pow(0.02, dt);
    }
    scene.sky.position.set(-swayX, -swayY, 0);

    cam.rotation.set(-inp.pitch, -inp.yaw, 0, "YXZ");
    if (inp.nativePose && inp.nativePose.position) {
      var p = inp.nativePose.position;
      cam.position.set(
        U.clamp(p.x || 0, -1.5, 1.5) + swayX,
        U.clamp(p.y || 0, -1.2, 1.2) + swayY,
        U.clamp(p.z || 0, -1.5, 1.5)
      );
    } else {
      cam.position.set(swayX, swayY, 0);
    }
    cam.updateMatrixWorld();

    // stereo copies get IPD offset at render time
    scene.cameraL.position.copy(cam.position);
    scene.cameraL.rotation.copy(cam.rotation);
    scene.cameraL.fov = cam.fov;
    scene.cameraR.position.copy(cam.position);
    scene.cameraR.rotation.copy(cam.rotation);
    scene.cameraR.fov = cam.fov;
  };

  /* ------------------------------------------------------------ hub items */

  var cardGeoCache = {};
  var CARD_W = 1.26;
  var CARD_H = 1.58;

  function cardGeometry(w, h, radius, bevel) {
    var key = [w, h, radius, bevel].join("_");
    if (cardGeoCache[key]) return cardGeoCache[key];
    var shape = new THREE.Shape();
    var x = -w / 2, y = -h / 2;
    shape.moveTo(x + radius, y);
    shape.lineTo(x + w - radius, y);
    shape.quadraticCurveTo(x + w, y, x + w, y + radius);
    shape.lineTo(x + w, y + h - radius);
    shape.quadraticCurveTo(x + w, y + h, x + w - radius, y + h);
    shape.lineTo(x + radius, y + h);
    shape.quadraticCurveTo(x, y + h, x, y + h - radius);
    shape.lineTo(x, y + radius);
    shape.quadraticCurveTo(x, y, x + radius, y);
    var geo = new THREE.ExtrudeGeometry(shape, {
      depth: 0.055,
      bevelEnabled: true,
      bevelThickness: bevel || 0.012,
      bevelSize: bevel || 0.012,
      bevelSegments: 2,
      curveSegments: 6
    });
    geo.center();
    // ExtrudeGeometry generates bevel-based UVs far outside 0..1. Remap the
    // front/back faces to the full texture and flatten the side faces so the
    // card shows exactly one copy of its artwork.
    remapCardUVs(geo, w, h, radius + (bevel || 0.012));
    cardGeoCache[key] = geo;
    return geo;
  }

  function remapCardUVs(geo, w, h, inset) {
    var pos = geo.attributes.position;
    var uv = geo.attributes.uv;
    if (!pos || !uv) return;
    var halfW = w / 2 + (inset || 0);
    var halfH = h / 2 + (inset || 0);
    for (var i = 0; i < pos.count; i++) {
      var x = pos.getX(i);
      var y = pos.getY(i);
      var u = (x + halfW) / (halfW * 2);
      var v = (y + halfH) / (halfH * 2);
      uv.setXY(i, U.clamp(u, 0, 1), U.clamp(v, 0, 1));
    }
    uv.needsUpdate = true;
  }

  function makeCardTexture(item, accent) {
    var W = 512, H = 642;
    var c = document.createElement("canvas");
    c.width = W;
    c.height = H;
    var g = c.getContext("2d");

    // Glass panel
    var grad = g.createLinearGradient(0, 0, W * 0.3, H);
    grad.addColorStop(0, "#1e2a4a");
    grad.addColorStop(1, "#0a0e1c");
    roundRect(g, 6, 6, W - 12, H - 12, 46);
    g.fillStyle = grad;
    g.fill();

    // card border
    g.lineWidth = 3;
    g.strokeStyle = "rgba(160, 200, 255, 0.20)";
    g.stroke();

    // top accent bar
    roundRect(g, 6, 6, W - 12, 8, 4);
    var ab = g.createLinearGradient(0, 0, W, 0);
    ab.addColorStop(0, accent);
    ab.addColorStop(1, "rgba(255,255,255,0)");
    g.fillStyle = ab;
    g.fill();

    // glow disc + icon
    var cx = W / 2, cy = 236;
    var rg = g.createRadialGradient(cx, cy, 10, cx, cy, 168);
    rg.addColorStop(0, hexA(accent, 0.38));
    rg.addColorStop(0.55, hexA(accent, 0.09));
    rg.addColorStop(1, hexA(accent, 0));
    g.fillStyle = rg;
    g.fillRect(0, 0, W, H * 0.78);

    var img = item.iconImage;
    if (img && img.complete && img.naturalWidth) {
      var size = 150;
      g.drawImage(img, cx - size / 2, cy - size / 2, size, size);
    } else {
      // fallback glyph while the SVG decodes
      g.strokeStyle = hexA(accent, 0.7);
      g.lineWidth = 6;
      g.beginPath();
      g.arc(cx, cy, 58, 0, Math.PI * 2);
      g.stroke();
    }

    // divider
    g.strokeStyle = "rgba(150,185,255,0.14)";
    g.lineWidth = 1.5;
    g.beginPath();
    g.moveTo(84, 404);
    g.lineTo(W - 84, 404);
    g.stroke();

    // title
    g.textAlign = "center";
    g.textBaseline = "middle";
    g.fillStyle = "#f2f6ff";
    g.font = "700 42px 'Space Grotesk', system-ui, sans-serif";
    fitText(g, item.title, W - 76, 42);
    g.fillText(item.title, cx, 442);

    // subtitle — up to two short lines
    g.fillStyle = "rgba(200, 216, 250, 0.62)";
    g.font = "500 25px 'Inter', system-ui, sans-serif";
    wrapLines(g, item.subtitle || "", W - 92, 484, 31, 2);

    var vg = g.createLinearGradient(0, H * 0.58, 0, H);
    vg.addColorStop(0, "rgba(8,12,24,0)");
    vg.addColorStop(1, "rgba(6,9,18,0.85)");
    g.fillStyle = vg;
    g.fillRect(6, H * 0.58, W - 12, H * 0.42);

    // bottom corner glyphs (signal a card, not a flat image)
    g.strokeStyle = "rgba(120, 200, 255, 0.25)";
    g.lineWidth = 2;
    g.beginPath();
    g.moveTo(28, H - 28);
    g.lineTo(28, H - 52);
    g.moveTo(28, H - 28);
    g.lineTo(52, H - 28);
    g.moveTo(W - 28, H - 28);
    g.lineTo(W - 28, H - 52);
    g.moveTo(W - 28, H - 28);
    g.lineTo(W - 52, H - 28);
    g.stroke();

    var tex = new THREE.CanvasTexture(c);
    tex.encoding = THREE.sRGBEncoding;
    tex.anisotropy = 4;
    tex.minFilter = THREE.LinearFilter;
    tex.magFilter = THREE.LinearFilter;
    tex.generateMipmaps = false;
    tex.needsUpdate = true;
    return tex;
  }

  function roundRect(g, x, y, w, h, r) {
    g.beginPath();
    g.moveTo(x + r, y);
    g.lineTo(x + w - r, y);
    g.quadraticCurveTo(x + w, y, x + w, y + r);
    g.lineTo(x + w, y + h - r);
    g.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
    g.lineTo(x + r, y + h);
    g.quadraticCurveTo(x, y + h, x, y + h - r);
    g.lineTo(x, y + r);
    g.quadraticCurveTo(x, y, x + r, y);
    g.closePath();
  }

  function fitText(g, text, maxW, baseSize) {
    var size = baseSize;
    while (g.measureText(text).width > maxW && size > 18) {
      size -= 2;
      g.font = "700 " + size + "px 'Space Grotesk', system-ui, sans-serif";
    }
  }

  function wrapLines(g, text, maxW, startY, lineH, maxLines) {
    var words = (text || "").split(/\s+/);
    var line = "";
    var lines = [];
    for (var i = 0; i < words.length; i++) {
      var test = line ? line + " " + words[i] : words[i];
      if (g.measureText(test).width > maxW && line) {
        lines.push(line);
        line = words[i];
      } else {
        line = test;
      }
    }
    if (line) lines.push(line);
    lines = lines.slice(0, maxLines);
    lines.forEach(function (l, i) {
      g.fillText(l, 256, startY + i * lineH);
    });
  }

  function hexA(hex, a) {
    var c = U.hexRgb(hex);
    return "rgba(" + c[0] + "," + c[1] + "," + c[2] + "," + a + ")";
  }

  /**
   * Create the hub carousel from the app definitions.
   * items: [{id,title,subtitle,badge,icon(accent),iconImage,onSelect}]
   */
  scene.buildHub = function (items, layout) {
    layout = layout || "carousel";
    scene.items = items;
    clearGroup(scene.hubGroup);

    var n = items.length;
    if (!n) return;

    // A carousel: every card sits on the same circle facing the viewer's
    // position, so one card is always dead centre no matter the aspect ratio.
    // 16° apart on a ring whose chord clears the card width. Portrait phones
    // have a narrow horizontal FOV, so the two neighbours peek in from the
    // edges and the rest sit at the sides where a head turn reveals them.
    var gapDeg = 17;
    var radius = CARD_W * 0.92 / (2 * Math.sin((gapDeg * Math.PI / 180) / 2));
    radius = U.clamp(radius, 2.4, 8.0);
    scene._hubGap = gapDeg * Math.PI / 180;
    var lift = -0.34;

    items.forEach(function (item, i) {
      var angle = (i / n) * Math.PI * 2;   // filled in by the animate loop

      var group = new THREE.Group();
      var tex = makeCardTexture(item, item.accent || "#3be8ff");
      var mat = new THREE.MeshBasicMaterial({
        map: tex,
        transparent: false,
        side: THREE.DoubleSide
      });
      var mesh = new THREE.Mesh(cardGeometry(CARD_W, CARD_H, 0.11, 0.014), mat);
      mesh.userData.itemIndex = i;
      mesh.userData.kind = "card";
      group.add(mesh);

      var halo = new THREE.Sprite(new THREE.SpriteMaterial({
        map: haloTexture(),
        color: new THREE.Color(item.accent || "#3be8ff"),
        transparent: true,
        opacity: 0.18,
        depthWrite: false,
        blending: THREE.AdditiveBlending
      }));
      halo.scale.set(2.0, 2.5, 1);
      halo.position.z = -0.10;
      group.add(halo);

      group.userData = {
        index: i,
        item: item,
        angle: angle,
        baseY: lift,
        hover: 0,
        appear: 0,
        mesh: mesh,
        halo: halo
      };
      group.scale.setScalar(0.001);
      group.visible = false;
      scene.hubGroup.add(group);
    });

    scene.hubRadius = radius;
    scene.hubFocus = 0;
    scene.hubFocusSmooth = 0;
    layoutHubCards(0, true);
  };

  /** Position every card on the carousel ring for a given focus offset. */
  function layoutHubCards(focus, instant) {
    var n = scene.hubGroup.children.length;
    if (!n) return;
    var radius = scene.hubRadius;
    scene.hubGroup.children.forEach(function (g, i) {
      var d = g.userData;
      if (!d) return;
      // shortest signed distance from the focused index around the ring
      var delta = i - focus;
      while (delta > n / 2) delta -= n;
      while (delta < -n / 2) delta += n;
      var angle = delta * (scene._hubGap || Math.PI * 2 / n);
      d.angle = angle;
      var front = Math.cos(angle);                     // 1 = centred
      var x = Math.sin(angle) * radius;
      var z = -Math.cos(angle) * radius;
      d.basePos = new THREE.Vector3(x, d.baseY, z);
      g.position.copy(d.basePos);
      g.lookAt(0, d.baseY, 0);
      d.baseQuat = g.quaternion.clone();
      g.visible = Math.abs(angle) < 1.45;              // hide what sits behind
      d.front = front;
    });
  }
  scene.layoutHubCards = layoutHubCards;

  /** Rebuild card artwork in place (icons finished loading, language change…). */
  scene.refreshHubTextures = function () {
    scene.hubGroup.children.forEach(function (g) {
      var d = g.userData;
      if (!d || !d.item || !d.mesh) return;
      var old = d.mesh.material.map;
      var tex = makeCardTexture(d.item, d.item.accent || "#3be8ff");
      d.mesh.material.map = tex;
      d.mesh.material.needsUpdate = true;
      if (old) old.dispose();
    });
  };

  var haloTextureCache = null;
  function haloTexture() {
    if (haloTextureCache) return haloTextureCache;
    var c = document.createElement("canvas");
    c.width = c.height = 256;
    var g = c.getContext("2d");
    var rg = g.createRadialGradient(128, 128, 6, 128, 128, 128);
    rg.addColorStop(0, "rgba(255,255,255,0.85)");
    rg.addColorStop(0.35, "rgba(255,255,255,0.28)");
    rg.addColorStop(0.7, "rgba(255,255,255,0.05)");
    rg.addColorStop(1, "rgba(255,255,255,0)");
    g.fillStyle = rg;
    g.fillRect(0, 0, 256, 256);
    haloTextureCache = new THREE.CanvasTexture(c);
    haloTextureCache.encoding = THREE.sRGBEncoding;
    return haloTextureCache;
  }

  function clearGroup(group) {
    while (group.children.length) {
      var child = group.children.pop();
      disposeTree(child);
    }
  }

  function disposeTree(obj) {
    obj.traverse(function (o) {
      if (o.geometry) o.geometry.dispose();
      if (o.material) {
        if (o.material.map && o.material.map !== haloTextureCache) o.material.map.dispose();
        o.material.dispose();
      }
    });
  }

  /* ---------------------------------------------------------- portal rings */

  scene.buildPortals = function (worlds) {
    clearGroup(scene.portalGroup);
    var R = 8.5;
    worlds.forEach(function (w, i) {
      var a = (i / worlds.length) * Math.PI * 2 + Math.PI * 0.15;
      var ring = new THREE.Mesh(
        new THREE.TorusGeometry(1.6, 0.035, 8, 48),
        new THREE.MeshBasicMaterial({
          color: new THREE.Color(w.accent),
          transparent: true,
          opacity: 0.35,
          depthWrite: false,
          blending: THREE.AdditiveBlending
        })
      );
      ring.position.set(Math.cos(a) * R, -0.4 + Math.sin(i * 2) * 0.8, Math.sin(a) * R);
      ring.lookAt(0, ring.position.y, 0);
      scene.portalGroup.add(ring);
    });
  };

  /* ------------------------------------------------------------- particles */

  var particleUniforms = null;
  scene.buildParticles = function (count) {
    clearGroup(scene.particleGroup);
    // The drifting motes read as stars, so only the night-time skies get them.
    var world = NX.worldById(scene.worldId || NX.settings.get("world"));
    if (world && (world.id === "beach" || world.id === "cinema")) {
      scene._particles = null;
      return;
    }
    count = count || (scene.quality === "low" ? 240 : scene.quality === "medium" ? 600 : 1100);
    var geo = new THREE.BufferGeometry();
    var pos = new Float32Array(count * 3);
    var seed = new Float32Array(count);
    var rng = Math.random;
    for (var i = 0; i < count; i++) {
      var r = 3 + rng() * 14;
      var th = rng() * Math.PI * 2;
      var ph = Math.acos(2 * rng() - 1);
      pos[i * 3] = Math.sin(ph) * Math.cos(th) * r;
      pos[i * 3 + 1] = Math.cos(ph) * r * 0.5 + 0.6;
      pos[i * 3 + 2] = Math.sin(ph) * Math.sin(th) * r;
      seed[i] = rng();
    }
    geo.setAttribute("position", new THREE.BufferAttribute(pos, 3));
    geo.setAttribute("aSeed", new THREE.BufferAttribute(seed, 1));

    var softDot = (function () {
      var c = document.createElement("canvas");
      c.width = c.height = 64;
      var g = c.getContext("2d");
      var rg = g.createRadialGradient(32, 32, 0, 32, 32, 32);
      rg.addColorStop(0, "rgba(255,255,255,1)");
      rg.addColorStop(0.4, "rgba(255,255,255,0.55)");
      rg.addColorStop(1, "rgba(255,255,255,0)");
      g.fillStyle = rg;
      g.fillRect(0, 0, 64, 64);
      var t = new THREE.CanvasTexture(c);
      t.encoding = THREE.sRGBEncoding;
      return t;
    })();
    var mat = new THREE.PointsMaterial({
      size: 0.075,
      map: softDot,
      color: 0xbfe6ff,
      alphaTest: 0.02,
      transparent: true,
      opacity: 0.5,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
      sizeAttenuation: true
    });
    var points = new THREE.Points(geo, mat);
    scene.particleGroup.add(points);
    scene._particles = { points: points, seed: seed, count: count };
  };

  /* ------------------------------------------------------------- picking */

  var _raycastList = [];

  scene.pick = function () {
    if (!scene.ready || !scene.items.length) return null;
    var x = NX.input.pointer.ndcX;
    var y = NX.input.pointer.ndcY;
    if (!NX.input.pointer.active) {
      // gaze mode: ray from the reticle centre
      x = 0;
      y = 0;
    }
    pointerNDC.set(x, y);
    raycaster.setFromCamera(pointerNDC, scene.camera);
    _raycastList.length = 0;
    scene.hubGroup.children.forEach(function (g) {
      if (g.userData && g.userData.mesh) _raycastList.push(g.userData.mesh);
    });
    var hits = raycaster.intersectObjects(_raycastList, false);
    if (!hits.length) return null;
    var hit = hits[0];
    var idx = hit.object.userData.itemIndex;
    return {
      index: idx,
      item: scene.items[idx],
      group: hit.object.parent,
      distance: hit.distance,
      point: hit.point,
      object: hit.object
    };
  };

  /** Bring card `index` to the front of the carousel. */
  scene.focusCard = function (index) {
    var n = scene.hubGroup.children.length;
    if (!n) return;
    index = ((index % n) + n) % n;
    // choose the nearest wrap so the carousel keeps spinning the short way
    var d = index - scene.hubFocus;
    while (d > n / 2) d -= n;
    while (d < -n / 2) d += n;
    scene.hubFocus += d;
    scene.hubFocusSmooth = scene.hubFocus;
    layoutHubCards(scene.hubFocusSmooth, true);
    scene._hoverIndex = ((index % n) + n) % n;
  };

  scene.stepCard = function (dir) {
    var n = scene.hubGroup.children.length;
    if (!n) return;
    scene.hubFocus += (dir > 0 ? 1 : -1);
    scene._hoverIndex = ((Math.round(scene.hubFocus) % n) + n) % n;
    layoutHubCards(scene.hubFocusSmooth, false);
  };

  scene.focusedIndex = function () {
    var n = scene.hubGroup.children.length;
    if (!n) return 0;
    return ((Math.round(scene.hubFocus) % n) + n) % n;
  };

  /* --------------------------------------------------------------- render */

  scene.render = function (dt) {
    if (!scene.ready) return;
    var r = scene.renderer;
    r.autoClear = true;
    if (scene.stereo) {
      renderStereo(dt);
      if (scene.flash > 0.002) scene.flash -= dt * 2.2;
      return;
    }
    renderMono(dt);
    if (scene.flash > 0.002) scene.flash -= dt * 2.2;
    var v = Math.max(0, scene.flash);
    r.setClearColor(0x03040a, 1);
    if (v > 0.002 && scene.camera) {
      // simple additive flash via the world's card halo
    }
  };

  function renderMono(dt) {
    var r = scene.renderer;
    r.setScissorTest(false);
    r.setViewport(0, 0, r.domElement.width, r.domElement.height);
    scene.camera.aspect = window.innerWidth / window.innerHeight;
    scene.camera.fov = NX.settings.get("fov") || 75;
    scene.camera.updateProjectionMatrix();
    r.render(scene.scene3, scene.camera);
  }

  function renderStereo(dt) {
    var r = scene.renderer;
    var w = r.domElement.width;
    var h = r.domElement.height;
    var halfW = Math.floor(w / 2);
    var ipd = 0.032 * (NX.settings.get("vrDistance") || 1);

    var cam = scene.camera;
    scene.cameraL.aspect = (halfW / h);
    scene.cameraL.updateProjectionMatrix();
    scene.cameraR.aspect = (halfW / h);
    scene.cameraR.updateProjectionMatrix();

    // offset each eye along the camera's local X axis
    var right = new THREE.Vector3(1, 0, 0).applyEuler(cam.rotation);
    scene.cameraL.position.copy(cam.position).addScaledVector(right, -ipd);
    scene.cameraR.position.copy(cam.position).addScaledVector(right, ipd);
    scene.cameraL.updateMatrixWorld();
    scene.cameraR.updateMatrixWorld();

    r.setScissorTest(true);
    r.setViewport(0, 0, halfW, h);
    r.setScissor(0, 0, halfW, h);
    r.render(scene.scene3, scene.cameraL);
    r.setViewport(halfW, 0, w - halfW, h);
    r.setScissor(halfW, 0, w - halfW, h);
    r.render(scene.scene3, scene.cameraR);
    r.setScissorTest(false);
  }

  scene.setStereo = function (on) {
    scene.stereo = !!on;
    scene.renderer.setScissorTest(false);
    scene.renderer.setViewport(0, 0, scene.renderer.domElement.width,
                               scene.renderer.domElement.height);
  };

  /* ------------------------------------------------------------- animation */

  scene.animate = function (dt, t) {
    if (!scene.ready) return;

    // carousel focus eases toward the selected card
    if (Math.abs(scene.hubFocusSmooth - scene.hubFocus) > 0.0004) {
      scene.hubFocusSmooth += (scene.hubFocus - scene.hubFocusSmooth) * U.damp(7, dt);
      if (Math.abs(scene.hubFocusSmooth - scene.hubFocus) < 0.0008) {
        scene.hubFocusSmooth = scene.hubFocus;
      }
      layoutHubCards(scene.hubFocusSmooth, false);
    }

    // floating cards
    scene.hubGroup.children.forEach(function (g) {
      var d = g.userData;
      if (!d || !g.visible) return;
      if (d.appearAt === undefined) d.appearAt = t + 0.05 + d.index * 0.055;
      var aT = U.clamp((t - d.appearAt) / 0.42, 0, 1);
      d.appear = aT < 1 ? aT : 1;
      var ease = 1 - Math.pow(1 - d.appear, 3);
      var bob = Math.sin(t * 0.9 + d.index * 0.7) * 0.040;
      var hoverTarget = (scene._hoverIndex === d.index) ? 1 : 0;
      d.hover += (hoverTarget - d.hover) * (1 - Math.exp(-9 * Math.min(dt, 0.1)));
      var focusAmt = U.clamp((d.front || 0) - 0.2, 0, 1);
      var s = ease * (0.86 + focusAmt * 0.14) * (1 + d.hover * 0.06);
      g.scale.setScalar(s);
      g.position.copy(d.basePos);
      g.position.y = d.baseY + bob + d.hover * 0.09;
      g.position.addScaledVector(d.basePos.clone().normalize(), d.hover * 0.26);
      g.quaternion.copy(d.baseQuat);
      if (d.halo) d.halo.material.opacity = (0.08 + focusAmt * 0.12) + d.hover * 0.26;
    });

    // portal rings
    scene.portalGroup.children.forEach(function (ring, i) {
      ring.rotation.z += dt * 0.22 * (i % 2 ? -1 : 1);
      ring.material.opacity = 0.22 + Math.sin(t * 1.2 + i) * 0.08;
    });

    // particles
    var particles = scene._particles;
    if (particles) {
      particles.points.rotation.y += dt * 0.012;
      var pos = particles.points.geometry.attributes.position;
      for (var i = 0; i < particles.count; i++) {
        var yi = 1 + i * 3;
        pos.array[yi] += dt * (0.03 + particles.seed[i] * 0.06);
        if (pos.array[yi] > 5.0) pos.array[yi] = -0.5;
      }
      pos.needsUpdate = true;
    }
  };

  /* -------------------------------------------------------------- resize */

  scene.observeHost = function () {
    if (!scene.ready || typeof ResizeObserver === "undefined" || scene._hostRO) return;
    var host = scene.host;
    if (!host) return;
    scene._hostRO = new ResizeObserver(function () { scene.resize(); });
    scene._hostRO.observe(host);
  };

  scene.resize = function () {
    if (!scene.ready) return;
    var host = scene.host || scene.renderer.domElement.parentElement;
    var w = (host && host.clientWidth) || window.innerWidth;
    var h = (host && host.clientHeight) || window.innerHeight;
    if (!w || !h) return;
    scene.renderer.setPixelRatio(fitPixelRatio());
    scene.renderer.setSize(w, h);
    scene.camera.aspect = w / h;
    scene.camera.updateProjectionMatrix();
    if (scene.stereo) {
      scene.cameraL.aspect = (w / 2) / h;
      scene.cameraR.aspect = (w / 2) / h;
      scene.cameraL.updateProjectionMatrix();
      scene.cameraR.updateProjectionMatrix();
    }
  };

  /* ------------------------------------------------------------- fx */

  scene.shake = function (amount) {
    state.shake = Math.max(state.shake, amount || 0.4);
  };

  scene.setQuality = function (q) {
    scene.quality = q;
    if (!scene.ready) return;
    scene.renderer.setPixelRatio(fitPixelRatio());
    scene.buildParticles();
  };

  scene.dispose = function () {
    if (!scene.ready) return;
    scene.renderer.dispose();
  };
})();
