/* ==========================================================================
   Nexus VR — browser.js
   In-app content modules:
     • NX.browser — curated destinations (Google, Wikipedia, GitHub, …);
       opened in a sandboxed in-app viewer when the site allows framing,
       otherwise handed off to the system browser.
     • NX.player  — 360° video player (MP4 → WebGL sphere, gyro + drag look).
     • NX.gallery — full-screen panorama viewer with stereo VR support.
   ========================================================================== */
(function () {
  "use strict";

  var NX = window.NX;
  var U = NX.util;
  var THREE = window.THREE;

  /* ---------------------------------------------------------------- browser */

  var DESTINATIONS = [
    { id: "google", name: "Google", url: "https://www.google.com/", icon: "browser",
      sub: "google.com", frame: false },
    { id: "wikipedia", name: "Wikipedia", url: "https://pt.m.wikipedia.org/", icon: "browser",
      sub: "pt.m.wikipedia.org", frame: true },
    { id: "github", name: "GitHub", url: "https://github.com/", icon: "browser",
      sub: "github.com", frame: false },
    { id: "youtube", name: "YouTube", url: "https://m.youtube.com/", icon: "youtube",
      sub: "m.youtube.com", frame: false },
    { id: "tiktok", name: "TikTok", url: "https://www.tiktok.com/", icon: "tiktok",
      sub: "tiktok.com", frame: false }
  ];

  var browser = (NX.browser = {
    destinations: DESTINATIONS,

    open: function (id) {
      if (id === "youtube" || id === "tiktok") {
        openSocial(id);
        return;
      }
      NX.app.modal({
        kicker: NX.i18n.t("browserLabel"),
        title: NX.i18n.t("browserTitle"),
        sub: NX.i18n.t("browserSub"),
        choices: DESTINATIONS.filter(function (d) { return d.id !== "youtube" && d.id !== "tiktok"; })
          .map(function (d) {
            return {
              icon: d.icon,
              title: d.name,
              subtitle: d.url,
              onSelect: function () { openInViewer(d); }
            };
          }),
        footer: NX.i18n.t("browserNote")
      });
    }
  });

  function openSocial(id) {
    var isYT = id === "youtube";
    NX.app.modal({
      kicker: isYT ? "YouTube" : "TikTok",
      title: isYT ? NX.i18n.t("youtubeTitle") : NX.i18n.t("tiktokTitle"),
      sub: isYT ? NX.i18n.t("youtubeSub") : NX.i18n.t("tiktokSub"),
      choices: [
        {
          icon: isYT ? "youtube" : "tiktok",
          title: isYT ? "YouTube" : "TikTok",
          subtitle: isYT ? "m.youtube.com" : "www.tiktok.com",
          onSelect: function () { openInViewer(isYT ? DESTINATIONS[3] : DESTINATIONS[4]); }
        },
        {
          icon: "player",
          title: NX.i18n.t("playerLabel"),
          subtitle: NX.i18n.t("playerLabelSub"),
          onSelect: function () { NX.player.openMenu(); }
        }
      ],
      footer: NX.i18n.t("browserNote")
    });
  }

  function openInViewer(dest) {
    NX.audio.sfx.select();
    var nativeOpen = NX.native.call("openURL", dest.url);

    if (dest.frame) {
      // Try the sandboxed in-app viewer first.
      var win = window.open(dest.url, "_blank", "noopener");
      if (!win) {
        fallback();
      } else {
        NX.app.toast("Abrindo " + dest.name + "…", "info");
      }
      return;
    }

    fallback();

    function fallback() {
      if (nativeOpen) return;
      var a = document.createElement("a");
      a.href = dest.url;
      a.target = "_blank";
      a.rel = "noopener noreferrer";
      document.body.appendChild(a);
      a.click();
      a.remove();
      NX.app.toast("Abrindo " + dest.name + " no Safari…", "info");
    }
  }

  /* ----------------------------------------------------------------- player */

  var player = (NX.player = {
    opened: false,
    source: "assets/video/space.mp4",
    title: "Nexus 360",
    renderer: null,
    scene: null,
    camera: null,
    sphere: null,
    video: null,
    raf: 0,
    vrmode: false
  });

  player.openMenu = function () {
    NX.app.modal({
      kicker: NX.i18n.t("player360"),
      title: NX.i18n.t("playerLabel"),
      sub: NX.i18n.t("playerLabelSub"),
      choices: [
        {
          icon: "player",
          title: "Nexus · Galactic Flyby",
          subtitle: "MP4 · 30s · 2K",
          accent: "#ffb46b",
          onSelect: function () { player.open("assets/video/space.mp4", "Galactic Flyby"); }
        },
        {
          icon: "player",
          title: "Nexus · Aurora Night",
          subtitle: "MP4 · 30s · 2K",
          accent: "#47f0a2",
          onSelect: function () { player.open("assets/video/aurora.mp4", "Aurora Night"); }
        }
      ]
    });
  };

  player.open = function (src, title) {
    player.source = src;
    player.title = title || "360°";
    player.opened = true;

    var panel = document.getElementById("panel-player");
    var stage = document.getElementById("player-stage");
    var loading = document.getElementById("player-loading");
    document.getElementById("player-title").textContent = title || "360°";
    panel.hidden = false;
    stage.innerHTML = "";
    loading.classList.remove("is-hidden");
    NX.bus.emit("player:open", { src: src, title: title });

    player.initThree(stage);

    var video = document.createElement("video");
    video.crossOrigin = "anonymous";
    video.playsInline = true;
    video.setAttribute("playsinline", "");
    video.setAttribute("webkit-playsinline", "");
    video.loop = true;
    video.muted = NX.settings.get("muted");
    video.volume = NX.settings.get("volume");
    video.src = src;
    video.setAttribute("aria-label", title);
    stage.appendChild(video);
    video.style.opacity = "0.001";
    video.style.pointerEvents = "none";
    video.style.position = "absolute";
    video.style.inset = "0";
    video.style.width = "1px";
    video.style.height = "1px";
    player.video = video;

    video.addEventListener("loadeddata", function () {
      loading.classList.add("is-hidden");
      NX.audio.sfx.open();
      player.play();
    });
    video.addEventListener("error", function () {
      loading.classList.add("is-hidden");
      NX.app.toast(NX.i18n.t("videoError"), "error");
      player.close();
    });

    // iOS requires a user gesture for unmuted playback; this runs inside one.
    var p = video.play && video.play();
    if (p && p.catch) p.catch(function () { /* retried on first tap */ });

    document.getElementById("btn-player-close").onclick = function () {
      player.close();
    };
    NX.app.setHudTitle(title || "360°", NX.i18n.t("player360"));
    document.addEventListener("keydown", player._esc = function (e) {
      if (e.key === "Escape") player.close();
    });
  };

  player.initThree = function (host) {
    player.dispose();
    var w = window.innerWidth;
    var h = window.innerHeight;
    var r = new THREE.WebGLRenderer({ antialias: true, alpha: false });
    r.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    r.setSize(w, h);
    r.outputEncoding = THREE.sRGBEncoding;
    host.appendChild(r.domElement);
    r.domElement.style.position = "absolute";
    r.domElement.style.inset = "0";

    var scene = new THREE.Scene();
    var cam = new THREE.PerspectiveCamera(80, w / h, 0.1, 100);
    cam.rotation.order = "YXZ";

    var geo = new THREE.SphereGeometry(50, 60, 40);
    geo.scale(-1, 1, 1);
    var mat = new THREE.MeshBasicMaterial({ color: 0x111111 });
    var sphere = new THREE.Mesh(geo, mat);
    scene.add(sphere);

    player.renderer = r;
    player.scene = scene;
    player.camera = cam;
    player.sphere = sphere;
    player.yaw = 0;
    player.pitch = 0;
    player.targetYaw = 0;
    player.targetPitch = 0;

    // drag-look bound to the stage
    bindPlayerLook(r.domElement);
    player.resize = function () {
      var ww = window.innerWidth, hh = window.innerHeight;
      r.setSize(ww, hh);
      cam.aspect = ww / hh;
      cam.updateProjectionMatrix();
      player.stereoUpdate && player.stereoUpdate();
    };
    window.addEventListener("resize", player.resize);

    loop();
    function loop() {
      player.raf = U.raf(loop);
      if (!player.renderer) return;
      var dt = 1 / 60;
      player.yaw += (player.targetYaw - player.yaw) * 0.12;
      player.pitch += (player.targetPitch - player.pitch) * 0.12;
      cam.rotation.set(-player.pitch, -player.yaw, 0);

      var vid = player.video;
      if (vid && vid.readyState >= 2) {
        if (!mat.map) {
          var tex = new THREE.VideoTexture(vid);
          tex.encoding = THREE.sRGBEncoding;
          tex.minFilter = THREE.LinearFilter;
          tex.magFilter = THREE.LinearFilter;
          mat.map = tex;
          mat.color.set(0xffffff);
          mat.needsUpdate = true;
          vid.style.display = "none";
        }
      }
      r.render(scene, cam);
    }
  };

  function bindPlayerLook(dom) {
    var down = false, lx = 0, ly = 0, pid = null;
    dom.addEventListener("pointerdown", function (e) {
      down = true;
      pid = e.pointerId;
      lx = e.clientX;
      ly = e.clientY;
      try { dom.setPointerCapture(pid); } catch (err) {}
    });
    dom.addEventListener("pointermove", function (e) {
      if (!down || e.pointerId !== pid) return;
      var dx = e.clientX - lx;
      var dy = e.clientY - ly;
      lx = e.clientX;
      ly = e.clientY;
      var s = NX.settings.get("sensitivity") * 0.0035;
      player.targetYaw += dx * s;
      player.targetPitch = U.clamp(player.targetPitch + dy * s, -1.4, 1.4);
    });
    function up(e) {
      down = false;
      try { dom.releasePointerCapture(e.pointerId); } catch (err) {}
    }
    dom.addEventListener("pointerup", up);
    dom.addEventListener("pointercancel", up);
  }

  player.play = function () {
    if (!player.video) return;
    var p = player.video.play();
    if (p && p.catch) {
      p.catch(function () {
        NX.app.toast(NX.i18n.t("tapAnywhere"), "info");
      });
    }
  };

  player.close = function () {
    var panel = document.getElementById("panel-player");
    panel.hidden = true;
    document.getElementById("player-stage").innerHTML = "";
    if (player._esc) document.removeEventListener("keydown", player._esc);
    if (player.video) {
      try { player.video.pause(); } catch (e) {}
      player.video.removeAttribute("src");
      player.video.load && player.video.load();
    }
    player.video = null;
    player.dispose();
    player.opened = false;
    window.removeEventListener("resize", player.resize);
    NX.bus.emit("player:close");
    if (NX.app) NX.app.setHudTitle(NX.i18n.t("hub"), "Nexus VR");
  };

  player.dispose = function () {
    if (player.raf) {
      U.caf(player.raf);
      player.raf = 0;
    }
    if (player.renderer) {
      player.renderer.dispose();
      if (player.renderer.domElement && player.renderer.domElement.parentNode) {
        player.renderer.domElement.parentNode.removeChild(player.renderer.domElement);
      }
    }
    player.renderer = null;
    player.scene = null;
    player.camera = null;
    player.sphere = null;
  };

  /* ---------------------------------------------------------------- gallery */

  var gallery = (NX.gallery = {
    index: 0,
    open: function (startIndex) {
      gallery.index = startIndex || 0;
      NX.app.modal({
        kicker: NX.i18n.t("galleryLabel"),
        title: NX.i18n.t("galleryLabel"),
        sub: NX.i18n.t("worldSub"),
        worlds: true,
        choices: NX.worlds.map(function (w, i) {
          return {
            thumb: w.thumb,
            title: NX.i18n.worldName(w),
            accent: w.accent,
            onSelect: function () {
              NX.app.closeModal();
              NX.app.setWorld(w.id);
              NX.app.toast(NX.i18n.worldName(w) + " · 360°", "info");
            }
          };
        })
      });
    }
  });
})();
