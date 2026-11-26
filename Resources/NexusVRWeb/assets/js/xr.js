/* ==========================================================================
   Nexus VR — xr.js
   Universal look/pointer input:
     • drag-to-look (touch + mouse, with inertia)
     • device orientation (gyroscope) — iOS permission flow included
     • NativeXR bridge (6DoF pose from ARKit/Vision inside a native app)
     • raycast hovering / clicking of 3D objects (gaze dwell + tap)
     • hand tracking data → normalized hand skeletons
   Stereo VR lives in scene.js (it owns the renderer/camera).
   ========================================================================== */
(function () {
  "use strict";

  var NX = window.NX;
  var U = NX.util;

  var input = (NX.input = {
    /** yaw/pitch in radians, used by scene.js as a target orientation */
    yaw: 0,
    pitch: -0.02,
    targetYaw: 0,
    targetPitch: -0.02,
    velocityYaw: 0,
    velocityPitch: 0,
    dragging: false,
    usable: true,
    gyroEnabled: false,
    gyroAvailable: false,
    gyroData: null,
    nativePose: null,
    hands: null,
    pointer: { x: 0.5, y: 0.5, active: false, ndcX: 0, ndcY: 0 },
    dwell: { time: 0, active: false, target: null },
    _lastMove: 0
  });

  /* ------------------------------------------------------------- drag-look */

  var surface = null;
  var pointerId = null;
  var lastX = 0;
  var lastY = 0;
  var startX = 0;
  var startY = 0;
  var movedDistance = 0;
  var pointerDownTime = 0;

  function attachDragSurface(el) {
    surface = el;
    el.addEventListener("pointerdown", onDown, { passive: false });
    el.addEventListener("pointermove", onMove, { passive: false });
    el.addEventListener("pointerup", onUp, { passive: false });
    el.addEventListener("pointercancel", onUp, { passive: false });
    el.addEventListener("pointerleave", onLeave, { passive: true });
    el.addEventListener("wheel", onWheel, { passive: false });
    el.addEventListener("contextmenu", function (e) { e.preventDefault(); });
  }

  function onDown(e) {
    if (pointerId !== null) return;
    // ignore drags that start on chrome
    if (e.target && e.target.closest && e.target.closest(".hud, .panel, .dock, .hudbtn, .gamepad, .player__head")) {
      return;
    }
    pointerId = e.pointerId;
    input.dragging = true;
    lastX = startX = e.clientX;
    lastY = startY = e.clientY;
    movedDistance = 0;
    pointerDownTime = U.now();
    input.velocityYaw = input.velocityPitch = 0;
    input.pointer.ndcX = (e.clientX / window.innerWidth) * 2 - 1;
    input.pointer.ndcY = -(e.clientY / window.innerHeight) * 2 + 1;
    input.pointer.x = e.clientX / window.innerWidth;
    input.pointer.y = e.clientY / window.innerHeight;
    try { surface.setPointerCapture(e.pointerId); } catch (err) {}
    NX.bus.emit("input:down", e);
    e.preventDefault();
  }

  function onMove(e) {
    if (e.pointerId !== pointerId) return;
    var dx = e.clientX - lastX;
    var dy = e.clientY - lastY;
    lastX = e.clientX;
    lastY = e.clientY;
    movedDistance += Math.abs(dx) + Math.abs(dy);
    var sens = NX.settings.get("sensitivity") * 0.0032;
    var inv = NX.settings.get("invertY") ? -1 : 1;
    input.targetYaw += dx * sens;
    input.targetPitch += dy * sens * 0.85 * inv;
    clampPitch();
    input.velocityYaw = dx * sens * 0.25;
    input.velocityPitch = dy * sens * 0.18 * inv;
    input._lastMove = U.now();
    NX.bus.emit("input:move", e);
    e.preventDefault();
  }

  function onUp(e) {
    if (e.pointerId !== pointerId) return;
    pointerId = null;
    input.dragging = false;
    var wasTap = movedDistance < 12 && U.now() - pointerDownTime < 0.55;
    try { surface.releasePointerCapture(e.pointerId); } catch (err) {}
    NX.bus.emit("input:up", { tap: wasTap, x: e.clientX, y: e.clientY });
    e.preventDefault();
  }

  function onLeave(e) {
    if (e.pointerId === pointerId) {
      pointerId = null;
      input.dragging = false;
    }
  }

  function onWheel(e) {
    // desktop convenience: wheel tilts the camera slightly
    var sens = NX.settings.get("sensitivity") * 0.0009;
    input.targetPitch += e.deltaY * sens;
    clampPitch();
    e.preventDefault();
  }

  function clampPitch() {
    var lim = Math.PI * 0.49;
    input.targetPitch = U.clamp(input.targetPitch, -lim, lim);
  }

  /* ----------------------------------------------------------- 6DoF bridge */

  /**
   * Application-facing API:
   *   NX.xr.setPose({yaw, pitch, position:{x,y,z}})   ← native app / demo
   *   NX.xr.setHands([{...}, {...}])
   *
   * The native code (Swift) should call window.NX.xr.* directly.
   */
  var xr = (NX.xr = {
    mode: "look",
    setPose: function (pose) {
      if (!pose) return;
      if (typeof pose.yaw === "number") {
        input.targetYaw = pose.yaw;
        input.yaw = pose.yaw;
      }
      if (typeof pose.pitch === "number") {
        input.targetPitch = U.clamp(pose.pitch, -Math.PI * 0.49, Math.PI * 0.49);
        input.pitch = input.targetPitch;
      }
      input.nativePose = {
        position: pose.position || { x: 0, y: 0, z: 0 },
        quaternion: pose.quaternion || null,
        timestamp: U.now()
      };
      NX.bus.emit("xr:pose", input.nativePose);
    },
    setHands: function (hands) {
      input.hands = hands || null;
      NX.bus.emit("xr:hands", input.hands);
    },
    /** convenience for native "touch" injection */
    tapAt: function (nx, ny) {
      input.pointer.ndcX = nx * 2 - 1;
      input.pointer.ndcY = -(ny * 2 - 1);
      NX.bus.emit("input:up", { tap: true, synthetic: true });
    },
    setMode: function (mode) {
      xr.mode = mode;
      NX.bus.emit("xr:mode", mode);
    },
    isNative: function () {
      return NX.native.available();
    },
    recenter: function () {
      input.targetYaw = 0;
      input.targetPitch = 0;
      input.yaw = 0;
      input.pitch = 0;
      if (input.gyroData) gyroRecentered = true;
      NX.bus.emit("xr:recenter");
    }
  });

  window.addEventListener("nexus-xr-pose", function (e) {
    xr.setPose(e.detail);
  });
  window.addEventListener("nexus-xr-hands", function (e) {
    xr.setHands(e.detail);
  });

  /* ------------------------------------------------------------- gyroscope */

  var gyroListening = false;
  var gyroRecentered = false;
  var gyroBase = null;

  xr.setGyro = function (on) {
    NX.settings.set("gyro", !!on);
    var st = NX.settings.all();
    if (on) {
      if (!input.gyroAvailable) {
        NX.bus.emit("toast", { text: NX.i18n.t("gyroSub"), kind: "warn" });
        return false;
      }
      startGyro();
    } else {
      stopGyro();
    }
    NX.bus.emit("toast", {
      text: NX.i18n.t(on ? "gyroOn" : "gyroOff"),
      kind: "info"
    });
    return true;
  };

  function startGyro() {
    if (gyroListening) return true;
    var DOE = window.DeviceOrientationEvent;
    if (!DOE) {
      input.gyroAvailable = false;
      return false;
    }
    gyroListening = true;
    window.addEventListener("deviceorientation", onDeviceOrientation, true);
    // some browsers deliver absolute orientation via devicemotion
    gyroRecentered = false;
    NX.bus.emit("gyro:start");
    return true;
  }

  function stopGyro() {
    if (!gyroListening) return;
    gyroListening = false;
    window.removeEventListener("deviceorientation", onDeviceOrientation, true);
    NX.bus.emit("gyro:stop");
  }

  function onDeviceOrientation(e) {
    if (!gyroListening) return;
    var alpha = e.alpha || 0;
    var beta = e.beta || 0;
    var gamma = e.gamma || 0;
    if (alpha === null || beta === null) return;

    var rad = Math.PI / 180;
    var a = alpha * rad, b = beta * rad, g = gamma * rad;

    // Convert device orientation quaternion → camera yaw/pitch
    var cA = Math.cos(a * 0.5), sA = Math.sin(a * 0.5);
    var cB = Math.cos(b * 0.5), sB = Math.sin(b * 0.5);
    var cG = Math.cos(g * 0.5), sG = Math.sin(g * 0.5);
    // ZYX order
    var qw = cA * cB * cG + sA * sB * sG;
    var qx = cA * cB * sG - sA * sB * cG;
    var qy = cA * sB * cG + sA * cB * sG;
    var qz = sA * cB * cG - cA * sB * sG;

    // forward vector from quaternion, then to yaw/pitch
    var fx = 2 * (qx * qz - qw * qy);
    var fy = 2 * (qy * qz + qw * qx);
    var fz = 1 - 2 * (qx * qx + qy * qy);
    // three.js camera looks down -Z, adjust for screen orientation
    var screenAngle = (screen.orientation && typeof screen.orientation.angle === "number")
      ? screen.orientation.angle
      : (window.orientation || 0);

    var yaw, pitch;
    if (Math.abs(screenAngle) === 90) {
      // landscape: swap forward axes
      if (screenAngle === 90) {
        yaw = Math.atan2(fx, fz);
        pitch = Math.asin(U.clamp(-fy, -1, 1));
      } else {
        yaw = Math.atan2(-fx, -fz);
        pitch = Math.asin(U.clamp(fy, -1, 1));
      }
    } else if (screenAngle === 180) {
      yaw = Math.atan2(-fz, -fx);
      pitch = Math.asin(U.clamp(-fy, -1, 1));
    } else {
      yaw = Math.atan2(fz, fx);
      pitch = Math.asin(U.clamp(-fy, -1, 1));
    }

    if (!gyroRecentered) {
      gyroBase = { yaw: yaw, pitch: pitch };
      gyroRecentered = true;
      input.yaw = input.targetYaw = yaw;
      input.pitch = input.targetPitch = pitch;
      return;
    }

    // yaw relative to recenter
    var dy = yaw - gyroBase.yaw;
    while (dy > Math.PI) dy -= Math.PI * 2;
    while (dy < -Math.PI) dy += Math.PI * 2;

    var sens = NX.settings.get("sensitivity");
    input.targetYaw = input.yaw + (dy - (input._gyroYaw || 0)) * sens;
    input._gyroYaw = dy;
    // pitch: follow absolute orientation
    input.targetPitch = pitch;
    clampPitch();
    input.gyroData = { alpha: alpha, beta: beta, gamma: gamma };
    NX.bus.emit("gyro:data", input.gyroData);
  }

  /**
   * Must be called from a user gesture on iOS 13+.
   * Returns a Promise<boolean>.
   */
  xr.requestGyroPermission = function () {
    var DOE = window.DeviceOrientationEvent;
    var result;
    if (DOE && typeof DOE.requestPermission === "function") {
      result = DOE.requestPermission().then(function (state) {
        input.gyroAvailable = state === "granted";
        if (input.gyroAvailable) startGyro();
        return input.gyroAvailable;
      }).catch(function () {
        input.gyroAvailable = false;
        return false;
      });
    } else {
      input.gyroAvailable = !!DOE;
      if (input.gyroAvailable) startGyro();
      result = Promise.resolve(input.gyroAvailable);
    }
    return result;
  };

  // Probe availability without prompting.
  if (window.DeviceOrientationEvent) input.gyroAvailable = true;

  /* -------------------------------------------------------------- gaze pick */

  /** Called by scene.js every frame with the hovered/clicked objects. */
  var pickState = { hovered: null, hitDistance: Infinity, hitPoint: null };

  function pickerUpdate(hovered, distance, point) {
    pickState.hovered = hovered;
    pickState.hitDistance = distance;
    pickState.hitPoint = point;
    var ret = NX.app && NX.app.reticle;
    if (ret) ret.classList.toggle("is-hover", !!hovered);
  }

  NX.input.pick = pickerUpdate;

  /* -------------------------------------------------------------- dwell logic */

  var DWELL_TIME = 1.15;

  function update(dt) {
    // smooth camera orientation
    var damp = U.damp(13, dt);
    if (input.gyroListening) damp = U.damp(22, dt);
    input.yaw += (input.targetYaw - input.yaw) * damp;
    input.pitch += (input.targetPitch - input.pitch) * damp;

    // inertia when the finger lifts
    if (!input.dragging && (Math.abs(input.velocityYaw) > 0.0001 || Math.abs(input.velocityPitch) > 0.0001)) {
      input.targetYaw += input.velocityYaw;
      input.targetPitch += input.velocityPitch;
      clampPitch();
      var decay = Math.pow(0.9, dt * 60);
      input.velocityYaw *= decay;
      input.velocityPitch *= decay;
    }

    // native pose override (native app streams absolute orientation)
    if (input.nativePose && U.now() - input.nativePose.timestamp < 0.5) {
      var p = input.nativePose;
      input.yaw = input.targetYaw = p.yaw != null ? p.yaw : input.yaw;
      input.pitch = input.targetPitch = p.pitch != null ? p.pitch : input.pitch;
    }

    // gaze dwell (hands-free clicking in VR headsets)
    if (input.handsActive && pickState.hovered) {
      var t = pickState.hovered;
      if (input.dwell.target === t) {
        input.dwell.time += dt;
      } else {
        input.dwell.target = t;
        input.dwell.time = 0;
      }
      if (input.dwell.time >= DWELL_TIME) {
        input.dwell.time = 0;
        input.dwell.target = null;
        NX.bus.emit("pick:click", t);
      }
    } else {
      input.dwell.time = 0;
      input.dwell.target = null;
    }

    NX.bus.emit("input:update", dt);
  }

  // A tap on the scene = click on the hovered object (handled in scene.js)
  NX.bus.on("input:up", function (e) {
    if (!e || !e.tap) return;
    NX.bus.emit("pick:tap", pickState.hovered);
  });

  NX.input.update = update;
  NX.input.attachDragSurface = attachDragSurface;
  NX.input.setHandsActive = function (on) {
    input.handsActive = !!on;
  };
})();
