/* ==========================================================================
   Nexus VR — app.js
   Application shell: boot sequence, entry ↔ world transitions, settings panel,
   modal system, toasts, stereo VR, resize and the master render loop.
   ========================================================================== */
(function () {
  "use strict";

  var NX = window.NX;
  var U = NX.util;

  var app = (NX.app = {
    mode: "boot",          // boot | entry | hub | game
    booted: false,
    lastT: 0,
    fps: 0,
    _fpsAcc: 0,
    _fpsFrames: 0,
    _hudStatusTimer: 0,
    _hintShown: false
  });

  // Boot bar progress is a simple staged animation
  function setBootProgress(pct, label) {
    var fill = document.getElementById("boot-bar-fill");
    var lab = document.getElementById("boot-label");
    if (fill) fill.style.width = pct + "%";
    if (lab && label) lab.textContent = label;
  }

  /* ------------------------------------------------------------------ toasts */

  NX.app.toast = function (text, kind, ms) {
    var stack = document.getElementById("toast-stack");
    if (!stack) return;
    var node = U.el("div", { class: "toast" + (kind ? " toast--" + kind : "") }, [
      U.el("span", { class: "toast__icon" }),
      U.el("span", { text: text })
    ]);
    stack.appendChild(node);
    var t = setTimeout(function () {
      node.classList.add("is-out");
      setTimeout(function () {
        if (node.parentNode) node.parentNode.removeChild(node);
      }, 380);
    }, ms || 2600);
    // cap the stack at 3
    while (stack.children.length > 3) stack.removeChild(stack.firstChild);
    return { dismiss: function () { clearTimeout(t); node.remove(); } };
  };

  NX.bus.on("toast", function (e) {
    if (!e) return;
    NX.app.toast(e.text, e.kind || "info", e.ms);
  });

  NX.bus.on("fatal", function (e) {
    var boot = document.getElementById("boot");
    if (boot) boot.classList.add("is-done");
    setBootProgress(100, e && e.message ? e.message : NX.i18n.t("webglFail"));
    NX.app.toast(e && e.message ? e.message : NX.i18n.t("webglFail"), "error", 7000);
  });

  /* ------------------------------------------------------------------- HUD */

  NX.app.setHudTitle = function (title, kicker) {
    var t = document.getElementById("hud-title");
    var k = document.getElementById("hud-kicker");
    if (t) t.textContent = title || "";
    if (k && kicker != null) k.textContent = kicker;
  };

  NX.app.setStatus = function (text, sticky) {
    var s = document.getElementById("hud-status");
    if (!s) return;
    s.innerHTML = text || "";
    if (!sticky) {
      clearTimeout(app._statusTimer);
      app._statusTimer = setTimeout(function () {
        if (s.innerHTML === text) s.innerHTML = "";
      }, 4200);
    }
  };

  NX.app.fpsLabel = function (fps) {
    return fps >= 50 ? "60 fps" : Math.round(fps) + " fps";
  };

  /* ----------------------------------------------------------------- modal */

  var overlayRoot = null;
  var modalState = { open: false, onClose: null };

  NX.app.modal = function (opts) {
    overlayRoot = document.getElementById("overlay-root");
    app.modalOpts = opts;
    modalState.open = true;
    var sheet = U.el("div", { class: "panel panel--modal" }, [
      U.el("div", { class: "panel__scrim", "data-close": true }),
      U.el("div", { class: "panel__sheet" }, [
        U.el("header", { class: "panel__head" }, [
          U.el("div", {}, [
            U.el("span", { class: "panel__kicker", text: opts.kicker || "" }),
            U.el("h2", { class: "panel__title", text: opts.title || "" })
          ]),
          U.el("button", { class: "iconbtn", type: "button", "data-close": true },
            [svgClose()])
        ]),
        U.el("div", { class: "panel__body" }, buildModalBody(opts))
      ])
    ]);
    overlayRoot.innerHTML = "";
    overlayRoot.appendChild(sheet);
    overlayRoot.hidden = false;
    NX.audio.sfx.click();
    overlayRoot.querySelectorAll("[data-close]").forEach(function (n) {
      n.addEventListener("click", function () { NX.app.closeModal(); });
    });
    // stagger the choices
    overlayRoot.querySelectorAll(".dest, .worldtile").forEach(function (n, i) {
      n.style.animation = "rise-in 0.45s var(--ease-out) both";
      n.style.animationDelay = (i * 0.035) + "s";
    });
    app.setStatus("");
  };

  function svgClose() {
    var wrap = document.createElement("span");
    wrap.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg>';
    return wrap.firstChild;
  }

  function buildModalBody(opts) {
    var frag = document.createDocumentFragment();
    if (opts.sub) {
      frag.appendChild(U.el("p", {
        text: opts.sub,
        style: {
          fontSize: "0.78rem", color: "var(--nx-ink-dim)", lineHeight: "1.5",
          margin: "2px 0 12px"
        }
      }));
    }
    if (opts.choices) {
      var list = U.el("div", { class: "destlist" });
      opts.choices.forEach(function (choice) {
        var iconEl;
        if (choice.thumb) {
          iconEl = U.el("img", { src: choice.thumb, alt: "" });
          var thumbWrap = U.el("div", {
            class: "dest__icon",
            style: { overflow: "hidden", padding: 0 }
          }, [iconEl]);
          iconEl.style.width = "100%";
          iconEl.style.height = "100%";
          iconEl.style.objectFit = "cover";
          iconEl.style.borderRadius = "10px";
          iconEl.style.display = "block";
          iconEl.style.borderRadius = "12px";
          iconEl.style.width = "38px";
          iconEl.style.height = "38px";
          iconEl.style.objectFit = "cover";
          iconEl.style.flex = "none";
          // Use a dedicated block so the icon keeps a square footprint.
          thumbWrap.removeChild(iconEl);
          thumbWrap.appendChild(iconEl);
          thumbWrap.style.borderRadius = "11px";
        } else if (choice.icon && NX.hub && NX.hub.icons) {
          iconEl = U.el("span", { style: { width: "22px", height: "22px", display: "block" } });
          iconEl.innerHTML = NX.hub.icons[choice.icon] || NX.hub.icons.browser;
          iconEl = U.el("div", { class: "dest__icon" }, [iconEl]);
        }
        var btn = U.el("button", { class: "dest", type: "button" }, [
          iconEl,
          U.el("div", { class: "dest__text" }, [
            U.el("span", { class: "dest__name", text: choice.title }),
            choice.subtitle ? U.el("span", { class: "dest__url", text: choice.subtitle }) : null
          ]),
          choice.badge ? U.el("span", {
            class: "player__badge",
            text: choice.badge,
            style: { marginLeft: "auto", flex: "none" }
          }) : null,
          U.el("span", { class: "dest__arrow" }, [svgArrow()])
        ]);
        if (choice.accent) {
          btn.style.setProperty("--accent", choice.accent);
          iconEl && (iconEl.style.borderColor = choice.accent + "55");
          iconEl && (iconEl.style.background = choice.accent + "18");
        }
        btn.addEventListener("click", function () {
          NX.audio.sfx.select();
          if (choice.onSelect) choice.onSelect();
        });
        list.appendChild(btn);
      });
      frag.appendChild(list);
    }
    if (opts.footer) {
      frag.appendChild(U.el("p", {
        text: opts.footer,
        style: {
          fontSize: "0.68rem", color: "var(--nx-ink-faint)", lineHeight: "1.5",
          marginTop: "14px", paddingTop: "12px", borderTop: "1px solid rgba(150,180,255,0.08)"
        }
      }));
    }
    return frag;
  }

  function svgArrow() {
    var w = document.createElement("span");
    w.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 5l7 7-7 7"/></svg>';
    return w.firstChild;
  }

  NX.app.closeModal = function () {
    if (!overlayRoot) overlayRoot = document.getElementById("overlay-root");
    overlayRoot.hidden = true;
    overlayRoot.innerHTML = "";
    modalState.open = false;
    NX.audio.sfx.back();
  };

  /* ------------------------------------------------------------- settings */

  NX.app.openSettings = function () {
    var panel = document.getElementById("panel-settings");
    var body = document.getElementById("settings-body");
    body.innerHTML = "";
    panel.hidden = false;
    NX.audio.sfx.click();
    buildSettings(body);
    panel.querySelectorAll("[data-close]").forEach(function (n) {
      n.onclick = function () { NX.app.closeSettings(); };
    });
  };

  NX.app.closeSettings = function () {
    document.getElementById("panel-settings").hidden = true;
    NX.audio.sfx.back();
  };

  function buildSettings(root) {
    var s = NX.settings.all();

    /* worlds */
    var worldGrid = U.el("div", { class: "worldgrid" });
    NX.worlds.forEach(function (w) {
      var tile = U.el("button", {
        class: "worldtile", type: "button",
        "aria-pressed": s.world === w.id ? "true" : "false",
        "data-world": w.id
      }, [
        U.el("img", { src: w.thumb, alt: "", loading: "lazy" }),
        U.el("span", { text: NX.i18n.worldName(w) })
      ]);
      tile.addEventListener("click", function () {
        NX.app.setWorld(w.id);
        worldGrid.querySelectorAll(".worldtile").forEach(function (t) {
          t.setAttribute("aria-pressed", t.getAttribute("data-world") === w.id ? "true" : "false");
        });
      });
      worldGrid.appendChild(tile);
    });
    root.appendChild(group("worldTitle", s.world, worldGrid, "worldSub"));

    /* audio */
    var sfxToggle = toggleRow("sfx", "sfxSub", !s.muted, function (on) {
      NX.settings.set("muted", !on);
      NX.app.toast(NX.i18n.t(on ? "soundOn" : "soundOff"), "info", 1600);
      if (on) NX.audio.unlock();
    });
    var volume = sliderRow("volume", "volume", s.volume, 0, 1, 0.05, function (v) {
      NX.settings.set("volume", v);
    }, function (v) { return Math.round(v * 100) + "%"; });
    root.appendChild(group("audio", null, U.el("div", { class: "slider-stack" }, [
      sfxToggle,
      volume.node
    ]), null));

    /* camera */
    var sens = sliderRow("sensitivity", null, s.sensitivity, 0.3, 2.4, 0.05, function (v) {
      NX.settings.set("sensitivity", v);
    }, function (v) { return v.toFixed(2) + "×"; });
    var fov = sliderRow("fov", null, s.fov, 60, 100, 1, function (v) {
      NX.settings.set("fov", v);
    }, function (v) { return Math.round(v) + "°"; });
    var gyro = toggleRow("gyro", "gyroSub", s.gyro, function (on) {
      if (on) {
        NX.xr.requestGyroPermission().then(function (ok) {
          if (!ok) {
            NX.app.toast(NX.i18n.t("gyroOff"), "warn");
          }
        });
      } else {
        NX.xr.setGyro(false);
      }
    });
    var invert = toggleRow("invertY", "invertYSub", s.invertY, function (on) {
      NX.settings.set("invertY", on);
    });
    root.appendChild(group("camera", null, U.el("div", { class: "slider-stack" }, [
      sens.node,
      U.el("p", { class: "slider__hint", text: NX.i18n.t("sensitivitySub") }),
      fov.node,
      gyro,
      invert,
      U.el("p", { class: "slider__hint", text: NX.i18n.t("cameraMode") + " · " + NX.i18n.t("camLook") + " / " + NX.i18n.t("camOrbit") })
    ]), null));

    /* interface */
    var uiScale = sliderRow("uiScale", null, s.uiScale, 0.85, 1.3, 0.05, function (v) {
      NX.settings.set("uiScale", v);
    }, function (v) { return Math.round(v * 100) + "%"; });
    var handsToggle = toggleRow("handTracking", "handTrackingSub", s.handTracking, function (on) {
      NX.hands.setEnabled(on);
    });
    var vrToggle = toggleRow("vrMode", "vrModeSub", s.vrMode, function (on) {
      NX.app.setStereo(on);
    });
    root.appendChild(group("interface", null, U.el("div", { class: "slider-stack" }, [
      uiScale.node,
      U.el("p", { class: "slider__hint", text: NX.i18n.t("uiScaleSub") }),
      handsToggle,
      vrToggle
    ]), null));

    /* quality */
    var seg = U.el("div", { class: "segmented" });
    [["auto", "qAuto"], ["high", "qHigh"], ["medium", "qMed"], ["low", "qLow"]].forEach(function (opt) {
      var b = U.el("button", {
        type: "button", text: NX.i18n.t(opt[1]),
        "aria-pressed": s.quality === opt[0] ? "true" : "false",
        "data-quality": opt[0]
      });
      b.addEventListener("click", function () {
        NX.settings.set("quality", opt[0]);
        NX.scene.setQuality(opt[0] === "auto" ? (NX.scene.quality || "medium") : opt[0]);
        seg.querySelectorAll("button").forEach(function (x) {
          x.setAttribute("aria-pressed", x.getAttribute("data-quality") === opt[0] ? "true" : "false");
        });
        NX.audio.sfx.click();
      });
      seg.appendChild(b);
    });
    var fpsToggle = toggleRow("showFps", "showFpsSub", s.showFps, function (on) {
      NX.settings.set("showFps", on);
    });
    var reduceToggle = toggleRow("reducedMotion", "reducedMotionSub", s.reducedMotion, function (on) {
      NX.settings.set("reducedMotion", on);
    });
    root.appendChild(group("quality", null, U.el("div", { class: "slider-stack" }, [
      seg, fpsToggle, reduceToggle
    ]), "performance"));

    /* language + reset */
    var langSeg = U.el("div", { class: "segmented" });
    [["pt", "Português"], ["en", "English"]].forEach(function (l) {
      var b = U.el("button", {
        type: "button", text: l[1],
        "aria-pressed": NX.i18n.lang() === l[0] ? "true" : "false"
      });
      b.addEventListener("click", function () {
        NX.i18n.set(l[0]);
        NX.app.closeSettings();
        NX.app.openSettings();
      });
      langSeg.appendChild(b);
    });
    var resetBtn = U.el("button", { class: "btn btn--ghost btn--danger", type: "button", text: NX.i18n.t("reset") });
    resetBtn.addEventListener("click", function () {
      NX.settings.reset();
      NX.app.applySettings();
      NX.app.closeSettings();
      NX.app.openSettings();
      NX.app.toast(NX.i18n.t("reset"), "info");
    });
    root.appendChild(group("language", null, U.el("div", { class: "slider-stack" }, [
      langSeg,
      resetBtn
    ]), null));
  }

  function group(titleKey, value, content, subKey) {
    var head = U.el("div", { class: "sgroup__head" }, [
      U.el("h3", { class: "sgroup__title", text: NX.i18n.t(titleKey) }),
      value != null ? U.el("span", { class: "sgroup__value", text: "" }) : null
    ]);
    var wrap = U.el("div", { class: "sgroup" }, [head]);
    if (typeof content === "string") {
      wrap.appendChild(U.el("p", { class: "slider__hint", text: content }));
    } else if (content) {
      wrap.appendChild(content);
    }
    if (subKey) {
      wrap.appendChild(U.el("p", {
        class: "slider__hint",
        style: { marginTop: "8px" },
        text: NX.i18n.t(subKey)
      }));
    }
    return wrap;
  }

  function sliderRow(labelKey, subKey, value, min, max, step, onChange, fmt) {
    var fill = ((value - min) / (max - min)) * 100;
    var input = U.el("input", {
      type: "range", min: min, max: max, step: step, value: value,
      "aria-label": NX.i18n.t(labelKey)
    });
    input.style.setProperty("--fill", fill + "%");
    var out = U.el("span", { class: "sgroup__value", text: (fmt || String)(value) });
    var head = U.el("div", { class: "slider__row" }, [
      U.el("span", { class: "slider__label", text: NX.i18n.t(labelKey) }),
      out
    ]);
    input.addEventListener("input", function () {
      var v = parseFloat(input.value);
      input.style.setProperty("--fill", (((v - min) / (max - min)) * 100) + "%");
      out.textContent = (fmt || String)(v);
      onChange(v);
    });
    var node = U.el("div", { class: "slider" }, [
      head,
      input,
      subKey ? U.el("span", { class: "slider__hint", text: NX.i18n.t(subKey) }) : null
    ]);
    return { node: node, input: input };
  }

  function toggleRow(labelKey, subKey, checked, onChange) {
    var sw = U.el("button", {
      class: "switch", type: "button", role: "switch",
      "aria-checked": checked ? "true" : "false",
      "aria-label": NX.i18n.t(labelKey)
    });
    sw.addEventListener("click", function () {
      var on = sw.getAttribute("aria-checked") !== "true";
      sw.setAttribute("aria-checked", on ? "true" : "false");
      NX.audio.sfx.click();
      onChange(on);
    });
    return U.el("div", { class: "toggle-row" }, [
      U.el("div", { class: "toggle-row__text" }, [
        U.el("span", { class: "toggle-row__title", text: NX.i18n.t(labelKey) }),
        subKey ? U.el("span", { class: "toggle-row__sub", text: NX.i18n.t(subKey) }) : null
      ]),
      sw
    ]);
  }

  /* --------------------------------------------------------------- settings wiring */

  NX.app.applySettings = function () {
    var s = NX.settings.all();
    document.documentElement.style.setProperty("--ui-scale", s.uiScale);
    if (NX.scene.ready) {
      NX.scene.camera.fov = s.fov;
      NX.scene.camera.updateProjectionMatrix();
    }
    if (document.body) document.body.classList.toggle("nx-reduced", !!s.reducedMotion);
    if (s.reducedMotion) document.documentElement.classList.add("nx-reduced-motion");
    else document.documentElement.classList.remove("nx-reduced-motion");
    app.setStereo(!!s.vrMode, true);
  };

  NX.bus.on("settings:change", function (e) {
    var s = NX.settings.all();
    if (e.key === "uiScale") {
      document.documentElement.style.setProperty("--ui-scale", e.value);
    } else if (e.key === "fov" && NX.scene.ready) {
      NX.scene.camera.fov = e.value;
      NX.scene.camera.updateProjectionMatrix();
    } else if (e.key === "vrMode") {
      app.setStereo(!!e.value);
    } else if (e.key === "world") {
      // handled by the caller that changed the setting (avoids recursion)
    } else if (e.key === "reducedMotion") {
      document.documentElement.classList.toggle("nx-reduced-motion", !!e.value);
    }
  });

  /* --------------------------------------------------------------- worlds */

  NX.app.setWorld = function (id) {
    var world = NX.worldById(id);
    NX.settings.set("world", id, { silent: true });
    var promise = NX.scene.setWorld(id);
    NX.audio.ambience(world.env);
    NX.app.setStatus(NX.i18n.t("loadingPanorama"), true);
    promise.then(function () {
      NX.app.setStatus("");
      NX.app.toast(NX.i18n.worldName(world) + " · 360°", "info", 1800);
    });
    return promise;
  };

  /* --------------------------------------------------------------- stereo VR */

  NX.app.setStereo = function (on, silent) {
    if (!NX.scene.ready) {
      NX.settings.set("vrMode", !!on, { silent: true });
      return;
    }
    NX.settings.set("vrMode", !!on, { silent: true });
    NX.scene.setStereo(on);
    document.getElementById("app").classList.toggle("is-vr", !!on);
    var vrBtn = document.getElementById("btn-vr");
    if (vrBtn) vrBtn.setAttribute("aria-pressed", on ? "true" : "false");
    overlayRoot = document.getElementById("overlay-root");

    var divider = document.querySelector(".vr-divider");
    var exit = document.querySelector(".vr-exit");
    if (on) {
      if (!divider) {
        divider = document.createElement("div");
        divider.className = "vr-divider";
        document.getElementById("world").appendChild(divider);
      }
      if (!exit) {
        exit = document.createElement("button");
        exit.className = "vr-exit";
        exit.type = "button";
        exit.textContent = "SAIR DO VR";
        exit.addEventListener("click", function () {
          NX.app.setStereo(false);
        });
        document.getElementById("world").appendChild(exit);
      }
      if (NX.app.closeModal) NX.app.closeModal();
      document.getElementById("panel-settings").hidden = true;
      var capEl = document.getElementById("hub-caption");
      if (capEl) capEl.hidden = true;
      var dockEl = document.getElementById("dock");
      dockEl.classList.remove("is-visible");
      dockEl.hidden = true;
      if (!silent) {
        NX.app.toast(NX.i18n.t("vrOn"), "info", 2000);
        setTimeout(function () {
          NX.app.toast(NX.i18n.t("vrHint"), "info", 4200);
        }, 700);
      }
      U.requestFullscreen();
    } else {
      if (divider) divider.remove();
      if (exit) exit.remove();
      if (!silent && silent !== undefined) NX.app.toast(NX.i18n.t("vrOff"), "info", 1600);
      var capShow = document.getElementById("hub-caption");
      if (capShow) capShow.hidden = false;
      if (NX.app.mode === "hub") {
        var dk = document.getElementById("dock");
        dk.hidden = false;
        dk.classList.add("is-visible");
      }
    }
  };

  function toggleStereo() {
    NX.app.setStereo(!NX.settings.get("vrMode"));
    NX.audio.sfx.select();
    U.haptic(10);
  }

  /* ------------------------------------------------------------- entry */

  function enter(forceVR) {
    if (app.mode === "hub") return;
    NX.audio.unlock();
    NX.audio.sfx.whoosh();
    var entry = document.getElementById("entry");
    entry.classList.add("is-leaving");
    // native app hand-off
    NX.native.emit("enter", { vr: !!forceVR });
    NX.native.call("setImmersive", true);

    var worldEl = document.getElementById("world");
    worldEl.hidden = false;
    worldEl.classList.add("is-fading-in");

    setTimeout(function () {
      entry.hidden = true;
      app.mode = "hub";
      NX.app.hudVisible(true);
      NX.app.setHudTitle(NX.i18n.t("hub"), "Nexus VR");
      if (!NX.scene.ready && !NX.scene.init(document.getElementById("world-stage"))) {
        return;
      }
      NX.app._inited = true;
      NX.hub.build();
      NX.scene.hubGroup.visible = true;
      // the world container was `hidden` during init: measure it now
      NX.scene.resize();
      NX.scene.observeHost();
      var worldId = NX.settings.get("world");
      NX.app.setWorld(worldId);
      NX.app.setStatus(NX.i18n.t("handHint"));

      if (forceVR || NX.settings.get("vrMode")) {
        NX.app.setStereo(true, true);
      } else {
        setTimeout(function () {
          var dock = document.getElementById("dock");
          dock.hidden = false;
          dock.classList.add("is-visible");
        }, 500);
      }
      if (NX.settings.get("gyro") && U.isTouch()) {
        NX.xr.requestGyroPermission().then(function (ok) {
          if (ok) NX.app.toast(NX.i18n.t("gyroHint"), "info", 2600);
        });
      }
      NX.bus.emit("app:enter");
    }, 620);
  }

  NX.app.hudVisible = function (on) {
    U.qsa(".hud, .reticle").forEach(function (el) {
      el.style.display = on ? "" : "none";
    });
  };

  function backToEntry() {
    if (app.mode === "entry") return;
    app.mode = "entry";
    NX.audio.sfx.back();
    NX.audio.ambience("calm");
    NX.scene.ready && (NX.scene.hubGroup.visible = false);
    app.setStereo(false, true);
    document.getElementById("panel-settings").hidden = true;
    document.getElementById("overlay-root").hidden = true;
    document.getElementById("world").hidden = true;
    var dockEl = document.getElementById("dock");
    dockEl.hidden = true;
    dockEl.classList.remove("is-visible");
    var cap = document.getElementById("hub-caption");
    if (cap) cap.hidden = true;
    var entry = document.getElementById("entry");
    entry.hidden = false;
    entry.classList.remove("is-leaving");
    if (NX.games && NX.games.active) NX.games.quit();
    NX.native.emit("exit", {});
    NX.native.call("setImmersive", false);
    // the entry canvas keeps rendering; re-measure in case of an orientation change
    if (NX.app.initEntryCanvas && !document.querySelector("#entry-canvas-host canvas")) {
      NX.app.initEntryCanvas();
    }
  }

  /* ------------------------------------------------------------- dock */

  function buildDock() {
    var dock = document.getElementById("dock");
    if (!dock) return;
    if (dock.children.length) return;
    (NX.hub.items || []).forEach(function (item) {
      var b = U.el("button", {
        class: "dock__item", type: "button",
        "aria-label": item.title, title: item.title,
        "data-id": item.id
      });
      var span = U.el("span", { style: { width: "24px", height: "24px" } });
      span.innerHTML = NX.hub.icons[item.icon] || "";
      b.appendChild(span);
      b.addEventListener("click", function () {
        NX.hub.select(item);
      });
      dock.appendChild(b);
    });
  }

  NX.bus.on("hub:built", buildDock);

  /* ------------------------------------------------------- hub caption */

  function setCaption(item) {
    var box = document.getElementById("hub-caption");
    if (!box) return;
    if (!item) {
      box.classList.remove("is-visible");
      return;
    }
    var t = document.getElementById("hub-caption-title");
    var sub = document.getElementById("hub-caption-sub");
    if (t) t.textContent = item.title;
    if (sub) sub.textContent = item.subtitle || "";
    box.classList.add("is-visible");
  }

  // hub chrome only makes sense in the hub
  function setHubChrome(visible) {
    var cap = document.getElementById("hub-caption");
    var dock = document.getElementById("dock");
    if (cap) cap.hidden = !visible;
    if (dock) {
      dock.hidden = !visible;
      dock.classList.toggle("is-visible", visible);
    }
  }

  NX.bus.on("game:start", function () { setHubChrome(false); });
  NX.bus.on("game:over", function () { setHubChrome(false); });
  NX.bus.on("game:quit", function () {
    if (app.mode === "hub" && !NX.scene.stereo) setHubChrome(true);
  });
  NX.bus.on("player:open", function () { setHubChrome(false); });
  NX.bus.on("player:close", function () {
    if (app.mode === "hub" && !NX.scene.stereo) setHubChrome(true);
  });

  NX.bus.on("hub:hover", setCaption);
  NX.bus.on("hub:built", function (items) { setCaption(items && items[0]); });
  NX.bus.on("hub:blur", function () { setCaption(null); });

  /* ------------------------------------------------------------- main loop */

  function loop(tms) {
    U.raf(loop);
    var t = (tms || 0) / 1000;
    var dt = app.lastT ? Math.min(0.05, t - app.lastT) : 0.016;
    app.lastT = t;

    NX.input.update(dt);

    if (NX.scene.ready) {
      NX.scene.updateCamera(dt);
      if (NX.scene.hubGroup.visible) {
        NX.scene.animate(dt, t);
        NX.hub.update(dt, t);
      }
      if (NX.games && NX.games.active) NX.games.update(dt, t);
      if (NX.hands) NX.hands.update(dt, t);
      NX.scene.render(dt);
    }

    // FPS counter
    app._fpsFrames++;
    app._fpsAcc += dt;
    if (app._fpsAcc >= 0.5) {
      app.fps = app._fpsFrames / app._fpsAcc;
      app._fpsFrames = 0;
      app._fpsAcc = 0;
      if (NX.settings.get("showFps") && app.mode === "hub") {
        NX.app.setStatus(NX.app.fpsLabel(app.fps) + " · " + (NX.scene.quality || ""), true);
      }
    }
  }

  /* ------------------------------------------------------------- listeners */

  function bindUi() {
    document.getElementById("btn-enter").addEventListener("click", function () {
      enter(false);
    });
    document.getElementById("btn-enter-vr").addEventListener("click", function () {
      app.setStereo(true);
      enter(true);
    });
    document.getElementById("btn-vr").addEventListener("click", toggleStereo);
    document.getElementById("btn-settings").addEventListener("click", function () {
      if (NX.games && NX.games.active) return;
      NX.app.openSettings();
    });
    document.getElementById("btn-back").addEventListener("click", function () {
      if (NX.games && NX.games.active) {
        NX.games.quit();
      } else {
        backToEntry();
      }
    });
    document.getElementById("btn-cam").addEventListener("click", function () {
      NX.xr.recenter();
      NX.audio.sfx.click();
      NX.app.toast(NX.i18n.t("dragHintShort"), "info", 1600);
    });
    document.getElementById("btn-sound-entry").addEventListener("click", function (e) {
      var on = e.currentTarget.getAttribute("aria-pressed") !== "true";
      e.currentTarget.setAttribute("aria-pressed", on ? "true" : "false");
      NX.settings.set("muted", !on);
      NX.audio.unlock();
      NX.app.toast(NX.i18n.t(on ? "soundOn" : "soundOff"), "info", 1500);
    });
    document.getElementById("btn-lang").addEventListener("click", function (e) {
      var next = NX.i18n.lang() === "pt" ? "en" : "pt";
      NX.i18n.set(next);
      e.currentTarget.textContent = next.toUpperCase();
    });
    document.getElementById("btn-ios-help").addEventListener("click", function () {
      document.getElementById("ios-sheet").hidden = false;
    });
    document.querySelectorAll("[data-ios-close]").forEach(function (n) {
      n.addEventListener("click", function () {
        document.getElementById("ios-sheet").hidden = true;
      });
    });

    // entry ambient motion: parallax background canvas
    var entryHost = document.getElementById("entry-canvas-host");

    window.addEventListener("resize", function () {
      NX.scene.resize && NX.scene.resize();
      var vd = document.querySelector(".vr-divider");
      if (vd) vd.style.left = "50%";
    });

    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") {
        if (!document.getElementById("panel-settings").hidden) NX.app.closeSettings();
        else if (!document.getElementById("overlay-root").hidden) NX.app.closeModal();
      }
      if ((e.key === "v" || e.key === "V") && app.mode === "hub" && !e.metaKey && !e.ctrlKey) {
        toggleStereo();
      }
      if ((e.key === "s" || e.key === "S") && app.mode === "hub" && !e.metaKey && !e.ctrlKey) {
        NX.app.openSettings();
      }
    });

    // Prevent iOS rubber-banding / double-tap zoom inside the app
    document.addEventListener("gesturestart", function (e) { e.preventDefault(); });
    var lastTouch = 0;
    document.addEventListener("touchend", function (e) {
      var now = Date.now();
      if (now - lastTouch < 300) e.preventDefault();
      lastTouch = now;
    }, { passive: false });
  }

  /* ----------------------------------------------------------------- boot */

  function boot() {
    setBootProgress(18, NX.i18n.t("loading"));
    NX.i18n.apply();
    document.documentElement.style.setProperty("--ui-scale", NX.settings.get("uiScale"));
    app.applySettings();

    // skip the loader fast on subsequent visits (cached)
    var started = U.now();
    var minBoot = 900;

    setTimeout(function () {
      setBootProgress(55);
    }, 300);

    setTimeout(function () {
      setBootProgress(100, NX.i18n.t("loading"));
      setTimeout(function () {
        var bootEl = document.getElementById("boot");
        bootEl.classList.add("is-done");
        setTimeout(function () { bootEl.style.display = "none"; }, 700);
        document.documentElement.classList.remove("nx-preload");
        document.getElementById("entry").classList.add("nx-enter-anim");
        app.mode = "entry";
        bindUi();
        NX.app.initEntryCanvas();
        U.raf(loop);
        NX.audio.ambience("calm");
        // preload one small panorama so entering is instant
        var img = new Image();
        img.src = NX.worldById(NX.settings.get("world")).lq;
        NX.scene.preloadWorlds && NX.scene.ready && NX.scene.preloadWorlds();
        app.booted = true;
        NX.bus.emit("app:booted");
      }, Math.max(0, minBoot - (U.now() - started)));
    }, 520);
  }

  /* --------------------------------------------- entry background (canvas) */

  NX.app.initEntryCanvas = function () {
    var host = document.getElementById("entry-canvas-host");
    if (!host || !window.THREE) return;
    try {
      var renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
      renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
      renderer.outputEncoding = THREE.sRGBEncoding;
      renderer.setClearColor(0x03040c, 1);
      host.appendChild(renderer.domElement);

      var scene = new THREE.Scene();
      var cam = new THREE.PerspectiveCamera(58, 1, 0.1, 200);

      /* ---------- stars ---------- */
      function dotTexture() {
        var c = document.createElement("canvas");
        c.width = c.height = 64;
        var g = c.getContext("2d");
        var rg = g.createRadialGradient(32, 32, 0, 32, 32, 32);
        rg.addColorStop(0, "rgba(255,255,255,1)");
        rg.addColorStop(0.35, "rgba(255,255,255,0.65)");
        rg.addColorStop(1, "rgba(255,255,255,0)");
        g.fillStyle = rg;
        g.fillRect(0, 0, 64, 64);
        return new THREE.CanvasTexture(c);
      }
      var starTex = dotTexture();

      function makeStars(count, radius, size, color, opacity) {
        var geo = new THREE.BufferGeometry();
        var pos = new Float32Array(count * 3);
        for (var i = 0; i < count; i++) {
          var r = radius * (0.7 + Math.random() * 0.6);
          var theta = Math.random() * Math.PI * 2;
          var phi = Math.acos(2 * Math.random() - 1);
          pos[i * 3] = r * Math.sin(phi) * Math.cos(theta);
          pos[i * 3 + 1] = Math.abs(r * Math.cos(phi)) * 0.7 + 1.0;
          pos[i * 3 + 2] = r * Math.sin(phi) * Math.sin(theta);
        }
        geo.setAttribute("position", new THREE.BufferAttribute(pos, 3));
        return new THREE.Points(geo, new THREE.PointsMaterial({
          color: color, size: size, map: starTex, alphaTest: 0.02,
          transparent: true, opacity: opacity,
          depthWrite: false, blending: THREE.AdditiveBlending, sizeAttenuation: true
        }));
      }
      var starGroup = new THREE.Group();
      starGroup.add(makeStars(700, 60, 0.16, 0xcfeaff, 0.85));
      starGroup.add(makeStars(260, 45, 0.30, 0xffffff, 0.55));
      starGroup.add(makeStars(160, 38, 0.42, 0xa8c8ff, 0.30));
      scene.add(starGroup);

      /* ---------- nebula glow sprites ---------- */
      function glowTexture(inner, outer) {
        var c = document.createElement("canvas");
        c.width = c.height = 256;
        var g = c.getContext("2d");
        var rg = g.createRadialGradient(128, 128, 4, 128, 128, 128);
        rg.addColorStop(0, inner);
        rg.addColorStop(0.45, outer);
        rg.addColorStop(1, "rgba(0,0,0,0)");
        g.fillStyle = rg;
        g.fillRect(0, 0, 256, 256);
        return new THREE.CanvasTexture(c);
      }
      var nebTex = glowTexture("rgba(120,90,255,0.55)", "rgba(60,40,140,0.10)");
      var nebula = new THREE.Sprite(new THREE.SpriteMaterial({
        map: nebTex, transparent: true, opacity: 0.55, depthWrite: false,
        blending: THREE.AdditiveBlending
      }));
      nebula.scale.set(46, 30, 1);
      nebula.position.set(-4, 8, -52);
      scene.add(nebula);

      var nebTex2 = glowTexture("rgba(60,220,255,0.42)", "rgba(20,90,140,0.07)");
      var nebula2 = new THREE.Sprite(new THREE.SpriteMaterial({
        map: nebTex2, transparent: true, opacity: 0.5, depthWrite: false,
        blending: THREE.AdditiveBlending
      }));
      nebula2.scale.set(38, 26, 1);
      nebula2.position.set(10, 4, -46);
      scene.add(nebula2);

      /* ---------- planet horizon ---------- */
      var planetGroup = new THREE.Group();
      var planet = new THREE.Mesh(
        new THREE.SphereGeometry(14, 72, 48),
        new THREE.MeshStandardMaterial({
          color: 0x03060c,
          roughness: 0.96,
          metalness: 0.04,
          emissive: 0x01040a,
          emissiveIntensity: 1.0
        })
      );
      // atmosphere shell
      var atmo = new THREE.Mesh(
        new THREE.SphereGeometry(14.42, 72, 48),
        new THREE.MeshBasicMaterial({
          color: 0x3be8ff, transparent: true, opacity: 0.055,
          side: THREE.BackSide, blending: THREE.AdditiveBlending, depthWrite: false
        })
      );
      planetGroup.add(planet, atmo);

      // rim light: a big additive ring hugging the horizon
      var rimTex = glowTexture("rgba(150,245,255,0.95)", "rgba(60,150,255,0.15)");
      var rimSprite = new THREE.Sprite(new THREE.SpriteMaterial({
        map: rimTex, transparent: true, opacity: 0.55, depthWrite: false,
        blending: THREE.AdditiveBlending
      }));
      rimSprite.scale.set(52, 9.5, 1);
      rimSprite.position.set(0, 13.96, 0);
      planetGroup.add(rimSprite);

      planetGroup.position.set(0, -14.5, 0);
      scene.add(planetGroup);

      /* ---------- orbit rings ---------- */
      var ringGroup = new THREE.Group();
      var ringA = new THREE.Mesh(
        new THREE.TorusGeometry(11.5, 0.020, 6, 220),
        new THREE.MeshBasicMaterial({
          color: 0x6fe8ff, transparent: true, opacity: 0.30,
          blending: THREE.AdditiveBlending, depthWrite: false
        })
      );
      ringA.rotation.x = Math.PI * 0.5 + 0.16;
      ringA.rotation.z = 0.12;
      ringGroup.add(ringA);
      var ringB = new THREE.Mesh(
        new THREE.TorusGeometry(13.9, 0.013, 6, 220),
        new THREE.MeshBasicMaterial({
          color: 0x9b7bff, transparent: true, opacity: 0.22,
          blending: THREE.AdditiveBlending, depthWrite: false
        })
      );
      ringB.rotation.x = Math.PI * 0.5 - 0.10;
      ringB.rotation.z = -0.30;
      ringGroup.add(ringB);
      ringGroup.position.copy(planetGroup.position).multiplyScalar(0.92);
      scene.add(ringGroup);

      /* ---------- lights ---------- */
      scene.add(new THREE.AmbientLight(0x4a6a9a, 0.22));
      var sun = new THREE.DirectionalLight(0xfff2d8, 1.2);
      sun.position.set(-9, 14, 4);
      scene.add(sun);
      var rim = new THREE.PointLight(0x3be8ff, 3.0, 60, 2);
      rim.position.set(6, 5, 6);
      scene.add(rim);
      var violet = new THREE.PointLight(0x8b6bff, 2.4, 60, 2);
      violet.position.set(-10, 3, -2);
      scene.add(violet);

      /* ---------- floaters ---------- */
      var floaters = [];
      var floaterShapes = [0, 1, 2, 0, 1];
      for (var f = 0; f < 5; f++) {
        var fg = floaterShapes[f] === 0
          ? new THREE.OctahedronGeometry(0.40, 0)
          : floaterShapes[f] === 1
            ? new THREE.TorusGeometry(0.40, 0.055, 6, 22)
            : new THREE.IcosahedronGeometry(0.42, 0);
        var floater = new THREE.Mesh(
          fg,
          new THREE.MeshBasicMaterial({
            color: f % 2 ? 0x3be8ff : 0x9b7bff,
            transparent: true,
            opacity: 0.42,
            wireframe: true,
            depthWrite: false
          })
        );
        // Keep a clear band around the centred logo/copy: only the corners.
        var slots = [
          [-4.5, 4.6], [4.7, 4.2], [-5.2, 1.2], [5.0, 0.4], [-1.2, 6.4]
        ];
        floater.position.set(
          slots[f][0] + (Math.random() - 0.5) * 0.8,
          slots[f][1] + (Math.random() - 0.5) * 0.6,
          -3.0 - Math.random() * 3.5
        );
        floater.userData = {
          spin: 0.2 + Math.random() * 0.5,
          bob: Math.random() * 6.28,
          baseY: floater.position.y
        };
        scene.add(floater);
        floaters.push(floater);
      }

      /* ---------- sizing / camera ---------- */
      var pointer = { x: 0, y: 0, tx: 0, ty: 0 };
      window.addEventListener("pointermove", function (e) {
        pointer.tx = ((e.clientX / window.innerWidth) - 0.5) * 2;
        pointer.ty = ((e.clientY / window.innerHeight) - 0.5) * 2;
      }, { passive: true });

      function resize() {
        var w = host.clientWidth || window.innerWidth;
        var h = host.clientHeight || window.innerHeight;
        renderer.setSize(w, h);
        cam.aspect = w / h;
        // On portrait screens pull the camera back so the horizon stays wide.
        var aspect = w / h;
        cam.position.set(0, 2.4, aspect < 1 ? 19 : 13.5);
        cam.lookAt(0, 1.1, 0);
        cam.fov = aspect < 1 ? 64 : 56;
        cam.updateProjectionMatrix();
        // keep the horizon just above the bottom third
        planetGroup.position.y = aspect < 1 ? -17.0 : -14.8;
        ringGroup.position.copy(planetGroup.position).multiplyScalar(0.92);
        var rs = aspect < 1 ? 1.0 : 1.15;
        ringGroup.scale.setScalar(rs);
      }
      resize();
      window.addEventListener("resize", resize);

      /* ---------- loop ---------- */
      var hidden = false;
      function tick(ms) {
        U.raf(tick);
        var entry = document.getElementById("entry");
        if (!entry || entry.hidden) {
          hidden = true;
          return;
        }
        if (hidden) {
          hidden = false;
          resize();
        }
        var t = ms / 1000;
        pointer.x += (pointer.tx - pointer.x) * 0.045;
        pointer.y += (pointer.ty - pointer.y) * 0.045;

        starGroup.rotation.y = t * 0.010;
        starGroup.rotation.x = pointer.y * 0.03;
        planet.rotation.y = t * 0.012;
        nebula.material.rotation = Math.sin(t * 0.04) * 0.10;
        nebula2.material.rotation = -Math.sin(t * 0.03) * 0.12;
        ringA.rotation.z = 0.12 + t * 0.010;
        ringB.rotation.z = -0.30 - t * 0.007;
        ringGroup.position.x = pointer.x * 0.25;
        floaters.forEach(function (flo, i) {
          flo.rotation.x += 0.004 * flo.userData.spin;
          flo.rotation.y += 0.006 * flo.userData.spin;
          flo.position.y = flo.userData.baseY + Math.sin(t * 0.5 + flo.userData.bob) * 0.35;
        });
        cam.position.x = pointer.x * 0.9;
        cam.position.y = 2.4 - pointer.y * 0.5;
        cam.lookAt(pointer.x * 0.4, 1.1, 0);
        renderer.render(scene, cam);
      }
      U.raf(tick);
    } catch (e) {
      if (window.console) console.warn("[NX] entry canvas failed", e);
    }
  };

  /* --------------------------------------------------------- native hooks */

  // The native app can jump straight into the hub:
  NX.app.enterFromNative = function (opts) {
    opts = opts || {};
    if (!app.booted) {
      document.addEventListener("app:booted", function () {
        enter(!!opts.vr);
      }, { once: true });
    } else {
      enter(!!opts.vr);
    }
    if (opts.world) NX.settings.set("world", opts.world, { silent: true });
  };

  /* ---------------------------------------------------------------- start */

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }

  // Expose minimal API for native code and tests
  window.NexusVR = {
    enter: NX.app.enterFromNative,
    exit: backToEntry,
    setWorld: NX.app.setWorld,
    setStereo: NX.app.setStereo,
    openSettings: NX.app.openSettings,
    version: NX.version
  };
})();
