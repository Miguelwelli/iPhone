/* ==========================================================================
   Nexus VR — hub.js
   App catalogue + hub construction + card interaction (hover, select).
   ========================================================================== */
(function () {
  "use strict";

  var NX = window.NX;
  var U = NX.util;

  /* ---------------------------------------------------------------- icons */

  // Inline SVG icons keep the bundle tiny and are crisp at any size.
  var ICONS = {
    youtube:
      '<svg viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">' +
      '<rect x="3" y="10" width="42" height="28" rx="9" fill="#ff2b3d"/>' +
      '<path d="M20 17.5v13l11-6.5-11-6.5z" fill="#fff"/></svg>',
    tiktok:
      '<svg viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">' +
      '<path d="M28.6 6h5.2c.4 3.7 2.6 6.6 6.2 7.2v5.2c-2.3-.1-4.5-.9-6.2-2.1v12.4c0 6.6-4.9 11.3-11.2 11.3-6.2 0-11.2-4.8-11.2-10.9 0-6 4.8-10.9 11-10.9.5 0 1 .04 1.5.1v5.5c-.5-.16-1-.24-1.5-.24-3.2 0-5.8 2.5-5.8 5.6 0 3.2 2.6 5.7 5.8 5.7s5.7-2.5 5.7-5.7V6z" fill="#fff"/></svg>',
    browser:
      '<svg viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">' +
      '<circle cx="24" cy="24" r="19" fill="none" stroke="#3be8ff" stroke-width="3"/>' +
      '<ellipse cx="24" cy="24" rx="8.5" ry="19" fill="none" stroke="#3be8ff" stroke-width="2.4"/>' +
      '<path d="M5.5 18h37M5.5 30h37" stroke="#3be8ff" stroke-width="2.4"/></svg>',
    games:
      '<svg viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">' +
      '<rect x="4" y="14" width="40" height="22" rx="10" fill="none" stroke="#47f0a2" stroke-width="3"/>' +
      '<path d="M15 21v8M11 25h8" stroke="#47f0a2" stroke-width="3" stroke-linecap="round"/>' +
      '<circle cx="32" cy="23" r="2.3" fill="#47f0a2"/><circle cx="37" cy="27.5" r="2.3" fill="#47f0a2"/></svg>',
    player:
      '<svg viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">' +
      '<circle cx="24" cy="24" r="17" fill="none" stroke="#ffb46b" stroke-width="2.6"/>' +
      '<path d="M20 16l12 8-12 8V16z" fill="#ffb46b"/></svg>',
    gallery:
      '<svg viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">' +
      '<rect x="6" y="10" width="36" height="26" rx="5" fill="none" stroke="#c3a6ff" stroke-width="2.6"/>' +
      '<circle cx="17" cy="20" r="3.4" fill="#c3a6ff"/>' +
      '<path d="M9 33l10-9 7 6 6-5 7 8z" fill="#c3a6ff" opacity=".85"/></svg>',
    settings:
      '<svg viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">' +
      '<circle cx="24" cy="24" r="6.5" fill="none" stroke="#9fb7ff" stroke-width="3"/>' +
      '<path d="M24 7l2.4 5.4 5.9-1 .7 5.9 5.4 2.4-3.1 5 3.1 5-5.4 2.4-.7 5.9-5.9-1L24 43l-2.4-5.4-5.9 1-.7-5.9L9.6 30l3.1-6-3.1-6 5.4-2.4.7-5.9 5.9 1z" fill="none" stroke="#9fb7ff" stroke-width="2.2" stroke-linejoin="round"/></svg>',
    vr:
      '<svg viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">' +
      '<path d="M7 16h34a2 2 0 0 1 2 2v10a4 4 0 0 1-6.8 2.9L32.5 27a8 8 0 0 0-11.4 0l-3.7 3.9A4 4 0 0 1 7 28V18a2 2 0 0 1 0-2z" fill="none" stroke="#ff4fa3" stroke-width="2.6"/></svg>'
  };

  /** Rasterize an inline SVG into an <img> so Three can draw it on a canvas. */
  function iconImage(name, size) {
    var svg = ICONS[name] || ICONS.browser;
    var img = new Image();
    img.decoding = "async";
    img.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg);
    return img;
  }

  NX.hub = {
    icons: ICONS,
    iconImage: iconImage
  };

  /* -------------------------------------------------------------- catalogue */

  var t = function (k) {
    return NX.i18n.t(k);
  };

  function apps() {
    return [
      {
        id: "youtube",
        title: t("youtubeTitle"),
        subtitle: t("youtubeSub"),
        accent: "#ff4f5e",
        icon: "youtube",
        badge: null,
        run: function () { NX.browser.open("youtube"); }
      },
      {
        id: "tiktok",
        title: t("tiktokTitle"),
        subtitle: t("tiktokSub"),
        accent: "#3be8ff",
        icon: "tiktok",
        badge: null,
        run: function () { NX.browser.open("tiktok"); }
      },
      {
        id: "browser",
        title: t("browserLabel"),
        subtitle: t("browserLabelSub"),
        accent: "#8b6bff",
        icon: "browser",
        run: function () { NX.browser.open("home"); }
      },
      {
        id: "games",
        title: t("gamesLabel"),
        subtitle: t("gamesLabelSub"),
        accent: "#47f0a2",
        icon: "games",
        run: function () { NX.games.openMenu(); }
      },
      {
        id: "player",
        title: t("playerLabel"),
        subtitle: t("playerLabelSub"),
        accent: "#ffb46b",
        icon: "player",
        run: function () { NX.player.openMenu(); }
      },
      {
        id: "gallery",
        title: t("galleryLabel"),
        subtitle: t("galleryLabelSub"),
        accent: "#c3a6ff",
        icon: "gallery",
        run: function () { NX.gallery.open(); }
      },
      {
        id: "settings",
        title: t("settingsLabel"),
        subtitle: t("settingsLabelSub"),
        accent: "#9fb7ff",
        icon: "settings",
        run: function () { NX.app.openSettings(); }
      }
    ];
  }

  /* ---------------------------------------------------------------- build */

  var currentItems = null;
  var hoverIndex = -1;
  var lastHoverEmit = 0;

  NX.hub.build = function (layout) {
    if (!NX.scene.ready) return;
    currentItems = apps().map(function (app) {
      return Object.assign({}, app, {
        iconImage: iconImage(app.icon, 128)
      });
    });
    NX.scene.buildHub(currentItems, layout || "arc");
    NX.scene.buildPortals(NX.worlds);
    NX.scene.buildParticles();
    NX.hub.items = currentItems;

    // The SVG data URLs decode asynchronously; rebuild once they're ready so
    // the card artwork includes the icons.
    var pending = currentItems.length;
    currentItems.forEach(function (item) {
      var done = function () {
        pending--;
        if (pending === 0) {
          NX.audio.hoverOnce = true;
          NX.scene.refreshHubTextures();
        }
      };
      if (item.iconImage.decode) {
        item.iconImage.decode().then(done).catch(done);
      } else if (item.iconImage.complete) {
        done();
      } else {
        item.iconImage.addEventListener("load", done, { once: true });
        item.iconImage.addEventListener("error", done, { once: true });
      }
    });

    NX.bus.emit("hub:built", currentItems);
  };

  NX.hub.items = null;

  /* --------------------------------------------------------------- picking */

  NX.hub.update = function (dt, tNow) {
    if (!NX.scene.ready || !NX.scene.items.length) return;
    var hit = NX.scene.pick();
    var idx = hit ? hit.index : -1;

    // Gaze / pointer hovers the card under the reticle; when nothing is under
    // it, highlight the card at the front of the carousel instead.
    if (idx < 0) idx = NX.scene.focusedIndex ? NX.scene.focusedIndex() : -1;
    NX.scene._hoverIndex = idx;

    if (idx !== hoverIndex) {
      hoverIndex = idx;
      if (NX.input.pick) NX.input.pick(hit ? hit.group : null, hit ? hit.distance : Infinity, hit ? hit.point : null);
      if (idx >= 0) {
        var now = U.now();
        if (now - lastHoverEmit > 0.05) {
          lastHoverEmit = now;
          NX.audio.sfx.hover();
          U.haptic(4);
        }
        NX.bus.emit("hub:hover", currentItems[idx]);
      } else {
        NX.bus.emit("hub:blur");
      }
    } else if (hit && NX.input.pick) {
      NX.input.pick(hit.group, hit.distance, hit.point);
    }

    // subtle per-frame card animation uses the hover index (scene.animate)
  };

  /** Called from a tap / pinch / native touch on a hovered card. */
  NX.hub.select = function (item) {
    item = item || (hoverIndex >= 0 ? currentItems[hoverIndex] : null);
    if (!item) return;
    NX.audio.sfx.select();
    NX.audio.sfx.open();
    U.haptic([8, 30, 12]);
    NX.bus.emit("hub:open", item);
    // small fly-in feel on the 3D side
    if (NX.scene.ready) NX.scene.flash = 0.45;
    if (typeof item.run === "function") item.run();
  };

  NX.bus.on("pick:tap", function (hit) {
    if (!currentItems) return;
    var idx = hit ? hit.index : (NX.scene.focusedIndex ? NX.scene.focusedIndex() : -1);
    var item = currentItems[idx];
    if (item) NX.hub.select(item);
  });

  NX.bus.on("pick:click", function (hit) {
    if (!hit) return;
    var item = currentItems && currentItems[hit.index];
    if (item) NX.hub.select(item);
  });

  // keyboard navigation for accessibility on desktop
  window.addEventListener("keydown", function (e) {
    if (!NX.scene.ready || !currentItems) return;
    if (!NX.app || NX.app.mode !== "hub") return;
    var cols = currentItems.length;
    if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
      e.preventDefault();
      NX.scene.stepCard(e.key === "ArrowRight" ? 1 : -1);
      hoverIndex = NX.scene.focusedIndex();
      NX.audio.sfx.hover();
      NX.bus.emit("hub:hover", currentItems[hoverIndex]);
    } else if (e.key === "Enter" || e.key === " ") {
      var ki = hoverIndex >= 0 ? hoverIndex : NX.scene.focusedIndex();
      if (currentItems[ki]) {
        e.preventDefault();
        NX.hub.select(currentItems[ki]);
      }
    }
  });

  var swipeStart = null;
  NX.bus.on("input:down", function (e) {
    if (!NX.app || NX.app.mode !== "hub" || !NX.scene.ready) return;
    swipeStart = { x: e.clientX, t: performance.now() };
  });
  NX.bus.on("input:up", function (e) {
    if (!NX.app || NX.app.mode !== "hub" || !NX.scene.ready || !swipeStart) return;
    var dx = e.x - swipeStart.x;
    var dtMs = performance.now() - swipeStart.t;
    swipeStart = null;
    if (dtMs < 700 && Math.abs(dx) > 46) {
      NX.scene.stepCard(dx < 0 ? 1 : -1);
      NX.audio.sfx.hover();
      U.haptic(6);
      NX.bus.emit("hub:hover", currentItems[NX.scene.focusedIndex()]);
    }
  });

  NX.bus.on("lang:change", function () {
    if (NX.app && NX.app.mode === "hub" && NX.scene.ready) {
      NX.hub.build();
      if (hoverIndex >= currentItems.length) hoverIndex = 0;
    }
  });
})();
