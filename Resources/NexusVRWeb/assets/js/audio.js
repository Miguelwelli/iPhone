/* ==========================================================================
   Nexus VR — audio.js
   Web Audio engine: procedural UI sounds, ambience beds and a lazy loader for
   real .wav files (assets/audio/*.wav) when they exist.

   iOS notes:
   - The AudioContext must be created/resumed inside a user gesture. Every
     public method funnels through `ensure()` which is only called from input
     handlers.
   - Fallback chain: Web Audio → HTMLAudioElement → silence. Never throws.
   ========================================================================== */
(function () {
  "use strict";

  var NX = window.NX;
  var U = NX.util;

  var ctx = null;
  var master = null;
  var sfxBus = null;
  var ambBus = null;
  var unlocked = false;
  var buffers = {};
  var activeAmb = null;
  var suspended = false;

  var SOUND_FILES = {
    click: "assets/audio/click.wav",
    hover: "assets/audio/hover.wav",
    select: "assets/audio/select.wav",
    back: "assets/audio/back.wav",
    error: "assets/audio/error.wav"
  };

  /* --------------------------------------------------------------- context */

  function AudioCtor() {
    return window.AudioContext || window.webkitAudioContext || null;
  }

  function ensure() {
    if (ctx || !AudioCtor()) return ctx;
    try {
      ctx = new (AudioCtor())();
      master = ctx.createGain();
      master.gain.value = 0;
      master.connect(ctx.destination);

      sfxBus = ctx.createGain();
      sfxBus.gain.value = 1;
      sfxBus.connect(master);

      ambBus = ctx.createGain();
      ambBus.gain.value = 0.0;
      ambBus.connect(master);

      applyVolume();
      loadSamples();
    } catch (e) {
      if (window.console) console.warn("[NX] AudioContext unavailable", e);
      ctx = null;
    }
    return ctx;
  }

  function unlock() {
    if (!ensure()) return false;
    try {
      if (ctx.state === "suspended") {
        var p = ctx.resume();
        if (p && p.catch) p.catch(function () {});
      }
      if (!unlocked) {
        unlocked = true;
        // A 1-sample silent buffer reliably unlocks WebAudio on iOS.
        var b = ctx.createBuffer(1, 1, 22050);
        var s = ctx.createBufferSource();
        s.buffer = b;
        s.connect(ctx.destination);
        s.start(0);
      }
      applyVolume();
      return true;
    } catch (e) {
      return false;
    }
  }

  function applyVolume() {
    var vol = NX.settings.get("volume");
    var muted = NX.settings.get("muted");
    if (!ctx || !master) return;
    var target = muted ? 0 : Math.pow(U.clamp(vol, 0, 1), 1.35) * 0.9;
    var t = ctx.currentTime;
    master.gain.cancelScheduledValues(t);
    master.gain.setTargetAtTime(target, t, 0.08);
  }

  function loadSamples() {
    Object.keys(SOUND_FILES).forEach(function (name) {
      var url = SOUND_FILES[name];
      var req = new XMLHttpRequest();
      req.open("GET", url, true);
      req.responseType = "arraybuffer";
      req.onload = function () {
        if (req.status !== 200 && req.status !== 0) return;
        if (!req.response || req.response.byteLength < 64) return;
        try {
          ctx.decodeAudioData(
            req.response.slice(0),
            function (buf) {
              buffers[name] = buf;
            },
            function () { /* not a valid wav — procedural sound is used */ }
          );
        } catch (e) { /* no-op */ }
      };
      req.onerror = function () {};
      try { req.send(); } catch (e) { /* no-op */ }
    });
  }

  /* ------------------------------------------------------------ synth voices */

  function envGain(t0, attack, hold, release, peak) {
    var g = ctx.createGain();
    var t = t0;
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(peak, t + attack);
    t += attack;
    g.gain.setValueAtTime(peak, t + hold);
    t += hold;
    g.gain.exponentialRampToValueAtTime(0.0001, t + release);
    return g;
  }

  function playBuffer(name, opts) {
    if (!buffers[name]) return false;
    var src = ctx.createBufferSource();
    src.buffer = buffers[name];
    var g = ctx.createGain();
    g.gain.value = (opts && opts.gain) || 0.9;
    src.connect(g);
    g.connect(sfxBus);
    try { src.start(0); } catch (e) { return false; }
    return true;
  }

  function tone(freq, opts) {
    opts = opts || {};
    var t0 = ctx.currentTime + (opts.delay || 0);
    var osc = ctx.createOscillator();
    var gain = ctx.createGain();
    osc.type = opts.type || "sine";
    osc.frequency.setValueAtTime(freq, t0);
    if (opts.slide) {
      osc.frequency.exponentialRampToValueAtTime(Math.max(20, opts.slide), t0 + (opts.dur || 0.2));
    }
    var peak = (opts.gain == null ? 0.16 : opts.gain);
    gain.gain.setValueAtTime(0.0001, t0);
    gain.gain.linearRampToValueAtTime(peak, t0 + (opts.attack || 0.008));
    gain.gain.exponentialRampToValueAtTime(0.0001, t0 + (opts.dur || 0.2));

    var out = gain;
    if (opts.filter) {
      var f = ctx.createBiquadFilter();
      f.type = opts.filter;
      f.frequency.value = opts.filterFreq || 1200;
      f.Q.value = opts.q || 0.8;
      gain.connect(f);
      out = f;
    }
    out.connect(sfxBus);
    osc.connect(gain);
    try {
      osc.start(t0);
      osc.stop(t0 + (opts.dur || 0.2) + 0.05);
    } catch (e) { /* no-op */ }
    return true;
  }

  function noise(opts) {
    opts = opts || {};
    var dur = opts.dur || 0.2;
    var len = Math.max(1, Math.floor(ctx.sampleRate * dur));
    var buf = ctx.createBuffer(1, len, ctx.sampleRate);
    var data = buf.getChannelData(0);
    for (var i = 0; i < len; i++) {
      data[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, opts.decay || 2.2);
    }
    var src = ctx.createBufferSource();
    src.buffer = buf;
    var f = ctx.createBiquadFilter();
    f.type = opts.filter || "bandpass";
    f.frequency.value = opts.freq || 1800;
    f.Q.value = opts.q || 0.9;
    var g = ctx.createGain();
    g.gain.value = opts.gain == null ? 0.12 : opts.gain;
    src.connect(f);
    f.connect(g);
    g.connect(sfxBus);
    try { src.start(0); } catch (e) { /* no-op */ }
    return true;
  }

  /* ---------------------------------------------------------------- public */

  var SFX = {
    click: function (gain) {
      if (playBuffer("click", { gain: gain })) return;
      tone(660, { type: "triangle", dur: 0.09, gain: 0.13, slide: 920 });
      tone(1320, { type: "sine", dur: 0.06, gain: 0.05, delay: 0.005 });
    },
    hover: function () {
      if (playBuffer("hover")) return;
      tone(1180, { type: "sine", dur: 0.05, gain: 0.035 });
    },
    select: function () {
      if (playBuffer("select")) return;
      tone(520, { type: "triangle", dur: 0.14, gain: 0.12, slide: 780 });
      tone(1040, { type: "sine", dur: 0.20, gain: 0.07, delay: 0.03 });
      tone(1560, { type: "sine", dur: 0.22, gain: 0.035, delay: 0.06 });
    },
    back: function () {
      if (playBuffer("back")) return;
      tone(780, { type: "triangle", dur: 0.14, gain: 0.10, slide: 420 });
    },
    error: function () {
      if (playBuffer("error")) return;
      tone(220, { type: "square", dur: 0.16, gain: 0.06, filter: "lowpass", filterFreq: 900 });
      tone(180, { type: "square", dur: 0.18, gain: 0.05, delay: 0.08, filter: "lowpass", filterFreq: 800 });
    },
    whoosh: function () {
      noise({ dur: 0.5, freq: 900, q: 0.6, gain: 0.06, decay: 1.4 });
    },
    open: function () {
      tone(300, { type: "sine", dur: 0.36, gain: 0.09, slide: 900 });
      noise({ dur: 0.35, freq: 2400, gain: 0.04, decay: 2.0 });
    },
    close: function () {
      tone(700, { type: "sine", dur: 0.28, gain: 0.07, slide: 260 });
    },
    coin: function () {
      tone(1046, { type: "triangle", dur: 0.09, gain: 0.10 });
      tone(1568, { type: "triangle", dur: 0.14, gain: 0.08, delay: 0.07 });
    },
    hit: function () {
      noise({ dur: 0.26, freq: 420, q: 0.5, gain: 0.16, decay: 1.6 });
      tone(90, { type: "sine", dur: 0.3, gain: 0.12, slide: 40 });
    },
    score: function () {
      tone(880, { type: "sine", dur: 0.10, gain: 0.07 });
      tone(1174, { type: "sine", dur: 0.12, gain: 0.06, delay: 0.06 });
    },
    gameover: function () {
      tone(392, { type: "triangle", dur: 0.22, gain: 0.09 });
      tone(311, { type: "triangle", dur: 0.24, gain: 0.08, delay: 0.18 });
      tone(233, { type: "triangle", dur: 0.5, gain: 0.08, delay: 0.36 });
    }
  };

  /* ------------------------------------------------------------- ambiences */

  var AMBIENCE = {
    /** wind + low drone for the night lake */
    calm: {
      gain: 0.20,
      build: function (bus) {
        var noiseSrc = loopNoise(bus, "lowpass", 420, 0.55, 0.55);
        var pad = drone(bus, [55, 82.5, 110], 0.16, "sine");
        var lfo = ctx.createOscillator();
        var lfoGain = ctx.createGain();
        lfo.frequency.value = 0.07;
        lfoGain.gain.value = 0.18;
        lfo.connect(lfoGain);
        lfoGain.connect(pad.gain);
        lfo.start();
        return [noiseSrc, pad.stop];
      }
    },
    deep: {
      gain: 0.16,
      build: function (bus) {
        var pad = drone(bus, [36.7, 55, 73.4], 0.20, "sine");
        var shimmer = drone(bus, [440, 660, 880], 0.012, "sine");
        return [pad.stop, shimmer.stop];
      }
    },
    sunny: {
      gain: 0.18,
      build: function (bus) {
        var surf = loopNoise(bus, "bandpass", 700, 0.6, 0.9);
        var wash = loopNoise(bus, "lowpass", 300, 0.5, 0.4);
        return [surf, wash];
      }
    },
    theatre: {
      gain: 0.13,
      build: function (bus) {
        var room = loopNoise(bus, "lowpass", 180, 0.4, 0.7);
        var drone3 = drone(bus, [48, 72], 0.10, "sine");
        return [room, drone3.stop];
      }
    },
    neon: {
      gain: 0.17,
      build: function (bus) {
        var pad = drone(bus, [65.4, 98, 130.8, 196], 0.10, "sawtooth", 620);
        var pulseLfo = ctx.createOscillator();
        var plg = ctx.createGain();
        pulseLfo.frequency.value = 0.45;
        plg.gain.value = 0.05;
        pulseLfo.connect(plg);
        plg.connect(pad.gain);
        pulseLfo.start();
        var air = loopNoise(bus, "highpass", 5200, 0.6, 0.12);
        return [pad.stop, air];
      }
    }
  };

  function loopNoise(bus, filterType, freq, q, gain) {
    var dur = 3.0;
    var len = Math.floor(ctx.sampleRate * dur);
    var buf = ctx.createBuffer(2, len, ctx.sampleRate);
    for (var ch = 0; ch < 2; ch++) {
      var data = buf.getChannelData(ch);
      var last = 0;
      for (var i = 0; i < len; i++) {
        var white = Math.random() * 2 - 1;
        last = last * 0.96 + white * 0.04; // brown-ish noise
        // crossfade loop boundaries
        var edge = Math.min(i, len - 1 - i) / (ctx.sampleRate * 0.35);
        data[i] = last * 8.0 * Math.min(1, edge);
      }
    }
    var src = ctx.createBufferSource();
    src.buffer = buf;
    src.loop = true;
    var f = ctx.createBiquadFilter();
    f.type = filterType;
    f.frequency.value = freq;
    f.Q.value = q;
    var g = ctx.createGain();
    g.gain.value = gain;
    src.connect(f);
    f.connect(g);
    g.connect(bus);
    try { src.start(0); } catch (e) { /* no-op */ }

    // subtle movement
    var lfo = ctx.createOscillator();
    var lg = ctx.createGain();
    lfo.frequency.value = 0.05 + Math.random() * 0.05;
    lg.gain.value = gain * 0.4;
    lfo.connect(lg);
    lg.connect(g.gain);
    lfo.start();

    return function stop() {
      try {
        src.stop(0);
        lfo.stop(0);
      } catch (e) { /* no-op */ }
    };
  }

  function drone(bus, freqs, gain, type, filterFreq) {
    var t0 = ctx.currentTime;
    var g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t0);
    g.gain.linearRampToValueAtTime(gain, t0 + 3.0);
    var out = g;
    if (filterFreq) {
      var f = ctx.createBiquadFilter();
      f.type = "lowpass";
      f.frequency.value = filterFreq;
      f.Q.value = 0.7;
      g.connect(f);
      out = f;
    }
    out.connect(bus);
    var oscs = freqs.map(function (fr, i) {
      var o = ctx.createOscillator();
      o.type = type || "sine";
      o.frequency.value = fr;
      o.detune.value = (i % 2 ? 6 : -6);
      o.connect(g);
      try { o.start(t0); } catch (e) {}
      return o;
    });
    return {
      gain: g,
      stop: function () {
        try {
          g.gain.setTargetAtTime(0.0001, ctx.currentTime, 0.4);
          oscs.forEach(function (o) {
            o.stop(ctx.currentTime + 2.0);
          });
        } catch (e) { /* no-op */ }
      }
    };
  }

  var stopCurrentAmb = null;

  var api = {
    unlock: unlock,
    enabled: function () {
      return !!ctx && !suspended;
    },
    sfx: SFX,

    /** Change the ambience bed; safe to call before unlocking. */
    ambience: function (name, opts) {
      if (!ctx) {
        // remember the intent, start once unlocked
        api._pendingAmb = name;
        return;
      }
      if (activeAmb === name && !(opts && opts.restart)) return;
      api.stopAmbience();
      var def = AMBIENCE[name];
      activeAmb = name;
      if (!def) return;
      try {
        var stoppers = def.build(ambBus);
        ambBus.gain.cancelScheduledValues(ctx.currentTime);
        ambBus.gain.setTargetAtTime(def.gain * (opts && opts.gain || 1), ctx.currentTime, 1.2);
        stopCurrentAmb = function () {
          stoppers.forEach(function (fn) {
            if (typeof fn === "function") fn();
          });
        };
      } catch (e) {
        if (window.console) console.warn("[NX] ambience failed", e);
      }
    },

    stopAmbience: function () {
      activeAmb = null;
      if (stopCurrentAmb) {
        try { stopCurrentAmb(); } catch (e) {}
        stopCurrentAmb = null;
      }
      if (ctx && ambBus) {
        ambBus.gain.setTargetAtTime(0.0001, ctx.currentTime, 0.4);
      }
    },

    suspend: function () {
      suspended = true;
      if (ctx && ctx.state === "running") {
        try { ctx.suspend(); } catch (e) {}
      }
    },

    resume: function () {
      suspended = false;
      if (ctx && ctx.state === "suspended") {
        try { ctx.resume(); } catch (e) {}
      }
      applyVolume();
      if (api._pendingAmb) {
        var p = api._pendingAmb;
        api._pendingAmb = null;
        api.ambience(p);
      }
    }
  };

  NX.audio = api;

  /* ----------------------------------------------------------- reactions */

  NX.bus.on("settings:change", function (e) {
    if (e.key === "volume" || e.key === "muted") applyVolume();
  });

  // unlock on the first gesture anywhere
  ["pointerdown", "touchstart", "keydown"].forEach(function (evt) {
    window.addEventListener(evt, function () {
      if (!ctx) {
        unlock();
        if (api._pendingAmb) {
          var p = api._pendingAmb;
          api._pendingAmb = null;
          api.ambience(p);
        }
      } else {
        unlock();
      }
    }, { passive: true, once: false });
  });

  // Pause when the page goes hidden (battery + iOS audio policy)
  document.addEventListener("visibilitychange", function () {
    if (document.hidden) {
      if (ctx && ctx.state === "running") {
        try { ctx.suspend(); } catch (e) {}
      }
    } else if (!suspended && ctx && ctx.state === "suspended") {
      try { ctx.resume(); } catch (e) {}
    }
  });
})();
