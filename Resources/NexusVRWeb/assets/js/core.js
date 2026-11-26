/* ==========================================================================
   Nexus VR — core.js
   Namespace, tiny helpers, persistence, event bus and settings store.
   Runs first; everything else augments window.NX.
   ========================================================================== */
(function () {
  "use strict";

  var NX = (window.NX = window.NX || {});

  /* ---------------------------------------------------------------- helpers */

  var U = (NX.util = {
    /** querySelector → array-ish helper */
    qs: function (sel, root) {
      return (root || document).querySelector(sel);
    },
    qsa: function (sel, root) {
      return Array.prototype.slice.call((root || document).querySelectorAll(sel));
    },
    /** Create a DOM element with attributes and children. */
    el: function (tag, attrs, children) {
      var node = document.createElement(tag);
      if (attrs) {
        Object.keys(attrs).forEach(function (k) {
          var v = attrs[k];
          if (v == null || v === false) return;
          if (k === "class") node.className = v;
          else if (k === "html") node.innerHTML = v;
          else if (k === "text") node.textContent = v;
          else if (k === "style" && typeof v === "object") {
            Object.keys(v).forEach(function (p) {
              node.style[p] = v[p];
            });
          } else if (k.slice(0, 2) === "on" && typeof v === "function") {
            node.addEventListener(k.slice(2).toLowerCase(), v);
          } else if (v === true) {
            node.setAttribute(k, "");
          } else {
            node.setAttribute(k, v);
          }
        });
      }
      if (children) {
        (Array.isArray(children) ? children : [children]).forEach(function (c) {
          if (c == null) return;
          node.appendChild(typeof c === "string" ? document.createTextNode(c) : c);
        });
      }
      return node;
    },
    clamp: function (v, lo, hi) {
      return v < lo ? lo : v > hi ? hi : v;
    },
    lerp: function (a, b, t) {
      return a + (b - a) * t;
    },
    /** frame-rate independent damping factor */
    damp: function (lambda, dt) {
      return 1 - Math.exp(-lambda * dt);
    },
    map: function (v, a, b, c, d) {
      return c + ((v - a) / (b - a)) * (d - c);
    },
    now: function () {
      return (window.performance && performance.now
        ? performance.now()
        : Date.now()) / 1000;
    },
    raf: function (fn) {
      return (window.requestAnimationFrame || function (f) { return setTimeout(f, 16); })(fn);
    },
    caf: function (id) {
      (window.cancelAnimationFrame || clearTimeout)(id);
    },
    isIOS: function () {
      var ua = navigator.userAgent || "";
      return /iPad|iPhone|iPod/.test(ua) ||
        (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
    },
    isSafari: function () {
      var ua = navigator.userAgent || "";
      return /Safari/.test(ua) && !/Chrome|Chromium|CriOS|FxiOS|Edg/.test(ua);
    },
    isTouch: function () {
      return ("ontouchstart" in window) || navigator.maxTouchPoints > 0;
    },
    isStandalone: function () {
      return ("standalone" in navigator && navigator.standalone) ||
        (window.matchMedia && matchMedia("(display-mode: standalone)").matches);
    },
    rafOnce: function (fn) {
      var started = false;
      U.raf(function (t) {
        if (started) return;
        started = true;
        fn(t);
      });
    },
    /** Hex → "r, g, b" CSS tuple */
    hexRgb: function (hex) {
      var h = hex.replace("#", "");
      if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
      var n = parseInt(h, 16);
      return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
    },
    debounce: function (fn, wait) {
      var t = 0;
      return function () {
        var self = this, args = arguments;
        clearTimeout(t);
        t = setTimeout(function () {
          fn.apply(self, args);
        }, wait);
      };
    },
    /** Safe vibrate (iOS ignores it, that's fine) */
    haptic: function (pattern) {
      try {
        if (navigator.vibrate) navigator.vibrate(pattern || 8);
      } catch (e) { /* no-op */ }
    },
    /** request fullscreen-ish immersive mode (best effort on iOS) */
    requestFullscreen: function () {
      var el = document.documentElement;
      var fn = el.requestFullscreen || el.webkitRequestFullscreen ||
        el.webkitEnterFullscreen || el.mozRequestFullScreen || el.msRequestFullscreen;
      if (fn) {
        try {
          var p = fn.call(el);
          if (p && p.catch) p.catch(function () {});
        } catch (e) { /* iOS Safari: not allowed for documents */ }
      }
      if (window.screen && screen.orientation && screen.orientation.lock) {
        try {
          screen.orientation.lock("landscape").catch(function () {});
        } catch (e) { /* no-op */ }
      }
    }
  });

  /* ------------------------------------------------------------------ events */

  var listeners = {};
  NX.bus = {
    on: function (name, fn) {
      (listeners[name] = listeners[name] || []).push(fn);
      return function () { NX.bus.off(name, fn); };
    },
    off: function (name, fn) {
      var arr = listeners[name];
      if (!arr) return;
      var i = arr.indexOf(fn);
      if (i >= 0) arr.splice(i, 1);
    },
    emit: function (name, payload) {
      var arr = listeners[name];
      if (!arr) return;
      arr.slice().forEach(function (fn) {
        try {
          fn(payload);
        } catch (e) {
          if (window.console) console.error("[NX] listener error:", name, e);
        }
      });
    }
  };

  /* ------------------------------------------------------------------ store */

  var KEY = "nexusvr.v1";

  NX.store = {
    read: function () {
      try {
        var raw = window.localStorage.getItem(KEY);
        return raw ? JSON.parse(raw) : null;
      } catch (e) {
        return null;
      }
    },
    write: function (obj) {
      try {
        window.localStorage.setItem(KEY, JSON.stringify(obj));
        return true;
      } catch (e) {
        return false;
      }
    },
    clear: function () {
      try { window.localStorage.removeItem(KEY); } catch (e) {}
    }
  };

  /* ----------------------------------------------------------------- worlds */

  /** World catalogue. Panorama paths are local and lazy-loaded. */
  NX.worlds = [
    {
      id: "night", name: "Noite", nameEn: "Night",
      pano: "assets/textures/panoramas/night.jpg",
      lq: "assets/textures/panoramas/night_lq.jpg",
      thumb: "assets/textures/thumbs/night.jpg",
      accent: "#47f0a2", fog: 0x040c14, exposure: 1.05,
      env: "calm", ambient: "#2a4a48"
    },
    {
      id: "space", name: "Espaço", nameEn: "Space",
      pano: "assets/textures/panoramas/space.jpg",
      lq: "assets/textures/panoramas/space_lq.jpg",
      thumb: "assets/textures/thumbs/space.jpg",
      accent: "#a98bff", fog: 0x05040e, exposure: 1.1,
      env: "deep", ambient: "#3a2f66"
    },
    {
      id: "beach", name: "Praia", nameEn: "Beach",
      pano: "assets/textures/panoramas/beach.jpg",
      lq: "assets/textures/panoramas/beach_lq.jpg",
      thumb: "assets/textures/thumbs/beach.jpg",
      accent: "#ffd27a", fog: 0x14324a, exposure: 1.02,
      env: "sunny", ambient: "#8a6a4a"
    },
    {
      id: "cinema", name: "Cinema", nameEn: "Cinema",
      pano: "assets/textures/panoramas/cinema.jpg",
      lq: "assets/textures/panoramas/cinema_lq.jpg",
      thumb: "assets/textures/thumbs/cinema.jpg",
      accent: "#ff6fae", fog: 0x0a0612, exposure: 1.18,
      env: "theatre", ambient: "#4a2440"
    },
    {
      id: "virtual", name: "Virtual", nameEn: "Virtual",
      pano: "assets/textures/panoramas/virtual.jpg",
      lq: "assets/textures/panoramas/virtual_lq.jpg",
      thumb: "assets/textures/thumbs/virtual.jpg",
      accent: "#ff4fa3", fog: 0x0d0618, exposure: 1.05,
      env: "neon", ambient: "#5a2050"
    }
  ];

  NX.worldById = function (id) {
    for (var i = 0; i < NX.worlds.length; i++) {
      if (NX.worlds[i].id === id) return NX.worlds[i];
    }
    return NX.worlds[0];
  };

  /* --------------------------------------------------------------- settings */

  var DEFAULTS = {
    world: "night",
    volume: 0.68,
    muted: false,
    sensitivity: 1.0,
    uiScale: 1.0,
    vrMode: false,
    gyro: true,
    handTracking: true,
    quality: "auto",           // auto | high | medium | low
    lang: "pt",
    reducedMotion: false,
    showFps: false,
    fov: 75,
    invertY: false
  };

  var state = Object.assign({}, DEFAULTS);

  var saved = NX.store.read();
  if (saved && typeof saved === "object") {
    Object.keys(DEFAULTS).forEach(function (k) {
      if (Object.prototype.hasOwnProperty.call(saved, k)) state[k] = saved[k];
    });
  }

  // Respect the OS reduced-motion preference on first run.
  if (!saved && window.matchMedia && matchMedia("(prefers-reduced-motion: reduce)").matches) {
    state.reducedMotion = true;
  }

  NX.settings = {
    defaults: DEFAULTS,
    all: function () {
      return state;
    },
    get: function (key) {
      return state[key];
    },
    set: function (key, value, opts) {
      if (state[key] === value) {
        if (!opts || !opts.silent) NX.bus.emit("settings:change", { key: key, value: value });
        return;
      }
      state[key] = value;
      NX.store.write(state);
      if (opts && opts.silent) return;
      NX.bus.emit("settings:change", { key: key, value: value });
    },
    patch: function (obj) {
      Object.keys(obj).forEach(function (k) {
        state[k] = obj[k];
      });
      NX.store.write(state);
      NX.bus.emit("settings:patch", obj);
    },
    reset: function () {
      Object.keys(DEFAULTS).forEach(function (k) {
        state[k] = DEFAULTS[k];
      });
      NX.store.write(state);
      NX.bus.emit("settings:reset", state);
    }
  };

  /* ---------------------------------------------------------- native bridge */

  /**
   * window.NativeXR — the bridge used when the app runs inside a native iOS
   * WKWebView container. All calls are guarded: in plain Safari they no-op.
   */
  NX.native = {
    available: function () {
      return !!(window.NativeXR && typeof window.NativeXR === "object");
    },
    call: function (method) {
      var args = Array.prototype.slice.call(arguments, 1);
      if (!NX.native.available()) return null;
      var fn = window.NativeXR[method];
      if (typeof fn !== "function") return null;
      try {
        return fn.apply(window.NativeXR, args);
      } catch (e) {
        if (window.console) console.warn("[NX] NativeXR." + method + " failed", e);
        return null;
      }
    },
    emit: function (name, detail) {
      if (!NX.native.available()) return;
      var fn = window.NativeXR.emit;
      if (typeof fn !== "function") return;
      try {
        fn.call(window.NativeXR, name, detail || {});
      } catch (e) { /* no-op */ }
    },
    vibrate: function (ms) {
      NX.native.call("haptic", typeof ms === "number" ? ms : 12);
    }
  };

  /* ---------------------------------------------------------------- version */

  NX.version = "1.0.0";
  NX.bootTime = U.now();
})();
