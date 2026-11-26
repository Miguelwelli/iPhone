/* ==========================================================================
   Nexus VR — hands.js
   Virtual hands in 3D (Three.js), fed by real ARKit hand tracking through the
   NativeXR bridge, or by a pointer-driven simulation when no native data is
   available (so desktop and mobile browsers still show working hands).

   Native contract (window.NativeXR / custom events):
     window.NX.xr.setHands({
       left:  { joints: { wrist:{x,y,z}, palm:{x,y,z}, thumbTip, indexTip, ... } },
       right: { ... },
       timestamp: 123.4
     })
   Positions are in metres in the shared AR space (y up, -z forward).
   Alternatively, normalized joints ({x,y,z} in 0..1 with z in metres) are
   accepted; `normalized: true` marks that form.
   ========================================================================== */
(function () {
  "use strict";

  var NX = window.NX;
  var U = NX.util;
  var THREE = window.THREE;

  var hands = (NX.hands = {
    enabled: false,
    active: false,
    source: "simulated",       // native | simulated
    hz: 0,
    _lastSample: 0,
    _samples: 0,
    _smoothed: null,
    left: null,
    right: null,
    ready: false
  });

  var JOINT_NAMES = [
    "wrist", "palm",
    "thumbMetacarpal", "thumbProximal", "thumbTip",
    "indexMetacarpal", "indexProximal", "indexTip",
    "middleMetacarpal", "middleProximal", "middleTip",
    "ringMetacarpal", "ringProximal", "ringTip",
    "littleMetacarpal", "littleProximal", "littleTip"
  ];

  // Skeleton edges (pairs of joint names) for the wireframe
  var EDGES = [
    ["wrist", "thumbMetacarpal"], ["thumbMetacarpal", "thumbProximal"],
    ["thumbProximal", "thumbTip"],
    ["wrist", "indexMetacarpal"], ["indexMetacarpal", "indexProximal"],
    ["indexProximal", "indexTip"],
    ["wrist", "middleMetacarpal"], ["middleMetacarpal", "middleProximal"],
    ["middleProximal", "middleTip"],
    ["wrist", "ringMetacarpal"], ["ringMetacarpal", "ringProximal"],
    ["ringProximal", "ringTip"],
    ["wrist", "littleMetacarpal"], ["littleMetacarpal", "littleProximal"],
    ["littleProximal", "littleTip"],
    ["indexMetacarpal", "middleMetacarpal"], ["middleMetacarpal", "ringMetacarpal"],
    ["ringMetacarpal", "littleMetacarpal"]
  ];

  var groups = {};
  var joints = {};
  var lines = {};
  var pinchRings = {};

  /* ------------------------------------------------------------- geometry */

  function buildHand(side, color) {
    if (!THREE) return null;
    var root = new THREE.Group();
    root.name = "hand-" + side;

    var jointGeo = new THREE.SphereGeometry(1, 10, 8);
    var jointMat = new THREE.MeshBasicMaterial({
      color: new THREE.Color(color),
      transparent: true,
      opacity: 0.92,
      fog: false
    });
    var tipMat = new THREE.MeshBasicMaterial({
      color: new THREE.Color("#ffffff"),
      transparent: true,
      opacity: 0.85,
      fog: false
    });

    var map = {};
    JOINT_NAMES.forEach(function (name) {
      var isTip = name.slice(-3) === "Tip";
      var isWrist = name === "wrist";
      var s = new THREE.Mesh(jointGeo, isTip ? tipMat : jointMat);
      var r = isWrist ? 0.0125 : (isTip ? 0.009 : 0.0075);
      s.scale.setScalar(r);
      s.visible = false;
      root.add(s);
      map[name] = s;
    });

    // bones: thin cylinders are expensive to resize; use a single dynamic line
    var linePositions = new Float32Array(EDGES.length * 6);
    var lineGeo = new THREE.BufferGeometry();
    lineGeo.setAttribute("position", new THREE.BufferAttribute(linePositions, 3));
    var lineMat = new THREE.LineBasicMaterial({
      color: new THREE.Color(color),
      transparent: true,
      opacity: 0.65,
      fog: false
    });
    var line = new THREE.LineSegments(lineGeo, lineMat);
    line.frustumCulled = false;
    line.visible = false;
    root.add(line);

    // pinch indicator ring (indexTip ↔ thumbTip)
    var ring = new THREE.Mesh(
      new THREE.TorusGeometry(0.014, 0.0022, 6, 18),
      new THREE.MeshBasicMaterial({
        color: new THREE.Color("#3be8ff"),
        transparent: true,
        opacity: 0,
        fog: false,
        depthWrite: false
      })
    );
    root.add(ring);

    return { root: root, joints: map, line: line, linePositions: linePositions, ring: ring };
  }

  function ensureBuilt() {
    if (!THREE || !NX.scene || !NX.scene.ready) return false;
    if (!hands.ready) {
      groups.left = buildHand("left", "#7ee7ff");
      groups.right = buildHand("right", "#c3a6ff");
      if (!groups.left || !groups.right) return false;
      hands.ready = true;
    }
    // Self-heal: scenes may be rebuilt (world switch) — re-attach if detached.
    ["left", "right"].forEach(function (side) {
      var g = groups[side];
      if (g && !g.root.parent) NX.scene.scene3.add(g.root);
    });
    return true;
  }

  /* ------------------------------------------------------------ data intake */

  /**
   * Normalize whatever shape the native bridge sends into a 17-joint,
   * metre-space skeleton. Accepts:
   *   { joints: {...}, normalized: true|false }
   *   { points: [ ... 17 metrics ] }
   */
  function normalizeHand(raw) {
    if (!raw) return null;
    var out = {};
    var scale = raw.normalized ? 1.35 : 1.0;   // normalize 0..1 → ~metres

    if (raw.joints) {
      JOINT_NAMES.forEach(function (name) {
        var j = raw.joints[name];
        if (!j) return;
        out[name] = {
          x: (j.x || 0) * scale,
          y: (j.y || 0) * scale,
          z: (j.z || 0) * scale
        };
      });
    } else if (raw.points && raw.points.length >= 17) {
      JOINT_NAMES.forEach(function (name, i) {
        var p = raw.points[i];
        out[name] = { x: (p.x || 0) * scale, y: (p.y || 0) * scale, z: (p.z || 0) * scale };
      });
    }

    if (!out.wrist) return null;
    // Fill any missing joints by interpolation from the wrist so nothing breaks.
    JOINT_NAMES.forEach(function (name) {
      if (!out[name]) {
        out[name] = { x: out.wrist.x, y: out.wrist.y - 0.06, z: out.wrist.z };
      }
    });
    return out;
  }

  function smooth(prev, next, amount) {
    if (!prev) return next;
    var out = {};
    Object.keys(next).forEach(function (name) {
      var a = prev[name] || next[name];
      var b = next[name];
      out[name] = {
        x: U.lerp(a.x, b.x, amount),
        y: U.lerp(a.y, b.y, amount),
        z: U.lerp(a.z, b.z, amount)
      };
    });
    return out;
  }

  function ingest(payload) {
    if (!hands.enabled) return;
    if (!ensureBuilt()) return;
    var now = U.now();
    var dt = hands._lastSample ? Math.max(0.001, now - hands._lastSample) : 0;
    hands._lastSample = now;
    hands._samples++;

    var smoothAmt = 0.45;
    if (payload && (payload.left || payload.right)) {
      hands.source = "native";
      var l = normalizeHand(payload.left);
      var r = normalizeHand(payload.right);
      var sm = hands._smoothed || {};
      hands.left = l ? (sm.left = smooth(sm.left, l, smoothAmt)) : null;
      hands.right = r ? (sm.right = smooth(sm.right, r, smoothAmt)) : null;
      hands._smoothed = sm;
      hands.active = !!(hands.left || hands.right);
      NX.bus.emit("hands:update", { left: hands.left, right: hands.right, source: "native" });
    }
  }

  // Native → JS
  window.addEventListener("nexus-xr-hands", function (e) {
    ingest(e.detail);
  });
  NX.bus.on("xr:hands", function (data) {
    ingest(data);
  });

  /* --------------------------------------------------------- pointer fallback */

  /**
   * When there's no native hand data, build a believable hand from the pointer
   * or the reticle so pointing/pinching still works with mouse, touch and gaze.
   */
  function simulate(dt, t) {
    if (hands.source === "native" && hands._lastSample &&
        U.now() - hands._lastSample < 2.5) {
      return;
    }
    hands.source = "simulated";
    var inp = NX.input;
    var visible = hands.enabled && (inp.hovering || inp.dragging || inp.pointer.active);

    // right hand follows the pointer/gaze; left hand rests lower-left
    var rightHand = simulatedHand("right", {
      yaw: inp.yaw + (inp.pointer.active ? inp.pointer.ndcX * 0.22 : 0),
      pitch: inp.pitch + (inp.pointer.active ? inp.pointer.ndcY * 0.14 : 0),
      z: -0.55,
      pinch: inp.pressed ? 1 : (NX.scene && NX.scene._hoverIndex >= 0 ? 0.22 : 0)
    }, t);

    var leftHand = simulatedHand("left", {
      yaw: inp.yaw - 0.30 + Math.sin(t * 0.6) * 0.02,
      pitch: inp.pitch - 0.22,
      z: -0.5,
      pinch: 0
    }, t + 1.7);

    hands.right = rightHand;
    hands.left = leftHand;
    hands.active = visible;
    if (visible) renderHand("right", hands.right, visible);
    if (visible) renderHand("left", hands.left, visible);
    if (!visible) hideHand("right"), hideHand("left");
    return visible;
  }

  function simulatedHand(side, opts, t) {
    var yaw = opts.yaw + (side === "right" ? 0.10 : -0.10);
    var pitch = opts.pitch - 0.32;
    var dist = Math.abs(opts.z);
    var origin = {
      x: Math.sin(yaw) * dist,
      y: Math.sin(pitch) * dist + 0.02,
      z: -Math.cos(yaw) * dist
    };
    var sideSign = side === "right" ? 1 : -1;
    var splay = 0.028 * sideSign;
    var joints = {};
    var names = ["thumb", "index", "middle", "ring", "little"];
    // palm orientation basis
    var right = { x: Math.cos(yaw), y: 0, z: Math.sin(yaw) };
    var up = { x: 0, y: 1, z: 0 };

    joints.wrist = { x: origin.x, y: origin.y - 0.05, z: origin.z };
    joints.palm = { x: origin.x, y: origin.y - 0.02, z: origin.z };

    names.forEach(function (name, i) {
      var spread = (i - 2) * 0.5;
      var reach = [0.065, 0.095, 0.100, 0.090, 0.072][i];
      var pinch = opts.pinch || 0;
      var curl = (name === "index" || name === "thumb") ? pinch * 0.65 : pinch * 0.35;
      var baseX = origin.x + right.x * (splay + spread * 0.026) + up.x * (0.02 - i * 0.002);
      var baseZ = origin.z + right.z * (splay + spread * 0.026);
      var tipX = baseX + up.x * (reach * (1 - curl)) + right.x * (spread * 0.02 - pinch * 0.03 * sideSign);
      var tipZ = baseZ + right.z * (spread * 0.02 - pinch * 0.03 * sideSign);
      var tipY = origin.y + 0.012 + reach * (1 - curl * 0.55) - curl * 0.035;
      joints[name + "Metacarpal"] = {
        x: origin.x + right.x * (splay + spread * 0.012),
        y: origin.y,
        z: origin.z + right.z * (splay + spread * 0.012)
      };
      joints[name + "Proximal"] = {
        x: baseX,
        y: origin.y + 0.02,
        z: baseZ
      };
      joints[name + "Tip"] = { x: tipX, y: tipY, z: tipZ };
    });
    return joints;
  }

  /* -------------------------------------------------------------- rendering */

  function renderHand(side, data, visible) {
    if (!hands.ready || !data) return;
    var g = groups[side];
    if (!g) return;
    g.root.visible = !!visible;
    if (!visible) return;

    var any = false;
    Object.keys(g.joints).forEach(function (name) {
      var mesh = g.joints[name];
      var j = data[name];
      if (!j) {
        mesh.visible = false;
        return;
      }
      mesh.visible = true;
      mesh.position.set(j.x, j.y, j.z);
      any = true;
    });

    // bones
    var arr = g.linePositions;
    for (var e = 0; e < EDGES.length; e++) {
      var a = data[EDGES[e][0]];
      var b = data[EDGES[e][1]];
      var o = e * 6;
      if (a && b) {
        arr[o] = a.x; arr[o + 1] = a.y; arr[o + 2] = a.z;
        arr[o + 3] = b.x; arr[o + 4] = b.y; arr[o + 5] = b.z;
      } else {
        arr[o] = arr[o + 1] = arr[o + 2] = arr[o + 3] = arr[o + 4] = arr[o + 5] = 0;
      }
    }
    g.line.geometry.attributes.position.needsUpdate = true;
    g.line.visible = true;

    // pinch ring between thumbTip and indexTip
    var thumb = data.thumbTip;
    var index = data.indexTip;
    if (thumb && index) {
      var mx = (thumb.x + index.x) / 2;
      var my = (thumb.y + index.y) / 2;
      var mz = (thumb.z + index.z) / 2;
      var d = Math.sqrt(
        Math.pow(thumb.x - index.x, 2) +
        Math.pow(thumb.y - index.y, 2) +
        Math.pow(thumb.z - index.z, 2)
      );
      g.ring.position.set(mx, my, mz);
      g.ring.lookAt(g.root.position.clone().set(0, 0, -10));
      var pinching = d < 0.032;
      g.ring.material.opacity += ((pinching ? 1 : 0.18) - g.ring.material.opacity) * 0.25;
      g.ring.material.color.set(pinching ? "#47f0a2" : "#3be8ff");
      g.ring.scale.setScalar(pinching ? 0.7 : 1);
      if (pinching) {
        g.ring.rotation.z += 0.06;
      }
    }
  }

  function hideHand(side) {
    if (!hands.ready) return;
    var g = groups[side];
    if (g) g.root.visible = false;
  }

  /* ------------------------------------------------------------ pinch logic */

  var wasPinching = false;
  var pinchCooldown = 0;

  function pinchCheck(dt) {
    if (!hands.enabled || !hands.active) return;
    var d = hands.right;
    if (!d || !d.thumbTip || !d.indexTip) return;
    var dist = Math.sqrt(
      Math.pow(d.thumbTip.x - d.indexTip.x, 2) +
      Math.pow(d.thumbTip.y - d.indexTip.y, 2) +
      Math.pow(d.thumbTip.z - d.indexTip.z, 2)
    );
    var pinch = dist < 0.030;
    pinchCooldown = Math.max(0, pinchCooldown - dt);
    if (pinch && !wasPinching && pinchCooldown === 0) {
      pinchCooldown = 0.35;
      NX.bus.emit("hands:pinch", { side: "right", distance: dist });
      NX.bus.emit("pick:click", NX.input.pick ? NX.input.pick() : null);
    }
    wasPinching = pinch;
  }

  /* --------------------------------------------------------------- public */

  hands.setEnabled = function (on) {
    hands.enabled = !!on;
    NX.settings.set("handTracking", hands.enabled);
    if (!hands.enabled) {
      hideHand("left");
      hideHand("right");
      hands.active = false;
      NX.input.setHandsActive(false);
    } else {
      ensureBuilt();
      NX.input.setHandsActive(true);
      // Native app: ask for the tracking session to start.
      NX.native.call("setHandTracking", true);
    }
    NX.bus.emit("toast", {
      text: NX.i18n.t(on ? "handDetected" : "handLost"),
      kind: on ? "info" : "warn"
    });
  };

  hands.update = function (dt, t) {
    if (!hands.enabled) return;
    if (!ensureBuilt()) return;

    if (hands.source === "native" && hands._lastSample &&
        U.now() - hands._lastSample < 2.5) {
      renderHand("left", hands.left, true);
      renderHand("right", hands.right, true);
      NX.input.setHandsActive(true);
      pinchCheck(dt);
      return;
    }

    // pointer/gaze driven fallback
    simulate(dt, t);
    if (hands.source === "simulated") {
      renderHand("left", hands.left, hands.active);
      renderHand("right", hands.right, hands.active);
    }
    pinchCheck(dt);
  };

  hands.stats = function () {
    return {
      enabled: hands.enabled,
      source: hands.source,
      active: hands.active,
      native: NX.native.available()
    };
  };

  // Track pointer pressed state for the simulated pinch
  NX.bus.on("input:down", function () { NX.input.pressed = true; });
  NX.bus.on("input:up", function () { NX.input.pressed = false; });

  NX.bus.on("settings:change", function (e) {
    if (e.key === "handTracking") {
      hands.enabled = !!e.value;
      if (hands.enabled) ensureBuilt();
      NX.input.setHandsActive(hands.enabled);
    }
  });

  NX.bus.on("scene:ready", function () {
    if (NX.settings.get("handTracking")) {
      hands.enabled = true;
      ensureBuilt();
      NX.input.setHandsActive(true);
    }
  });
})();
