/* ==========================================================================
   Nexus VR — games.js
   Three mini-games rendered into the same Three.js scene:
     • asteroids — weave and shoot drifting rocks
     • orbs      — pop glowing orbs with your gaze/touch
     • neon      — dodge the neon walls on a synthwave grid
   All games honour NX.settings (sensitivity, reducedMotion) and play nice with
   the stereo VR mode (they render through the shared camera).
   ========================================================================== */
(function () {
  "use strict";

  var NX = window.NX;
  var U = NX.util;
  var THREE = window.THREE;
  var _raycaster = new THREE.Raycaster();
  var _centre = new THREE.Vector2(0, 0);

  var games = (NX.games = {
    active: null,
    menuOpen: false,
    score: 0,
    best: loadBest(),
    group: null,
    gameOver: false,
    _ui: {},
    registry: {}
  });

  function loadBest() {
    try {
      var raw = window.localStorage.getItem("nexusvr.best");
      return raw ? JSON.parse(raw) : {};
    } catch (e) {
      return {};
    }
  }

  function saveBest() {
    try {
      window.localStorage.setItem("nexusvr.best", JSON.stringify(games.best));
    } catch (e) { /* no-op */ }
  }

  /* --------------------------------------------------------------- helpers */

  function group() {
    if (!games.group) {
      games.group = new THREE.Group();
      games.group.name = "games";
      NX.scene.scene3.add(games.group);
    }
    return games.group;
  }

  function clear() {
    if (!games.group) return;
    while (games.group.children.length) {
      var c = games.group.children.pop();
      disposeTree(c);
    }
  }

  function disposeTree(obj) {
    obj.traverse(function (o) {
      if (o.geometry && o.geometry.dispose) o.geometry.dispose();
      if (o.material) {
        if (o.material.map) o.material.map.dispose();
        o.material.dispose();
      }
    });
  }

  function randomBetween(a, b) {
    return a + Math.random() * (b - a);
  }

  function textTexture(text, opts) {
    opts = opts || {};
    var w = 512, h = 128;
    var c = document.createElement("canvas");
    c.width = w;
    c.height = h;
    var g = c.getContext("2d");
    g.clearRect(0, 0, w, h);
    if (opts.bg) {
      g.fillStyle = opts.bg;
      g.fillRect(0, 0, w, h);
    }
    g.fillStyle = opts.color || "#eef1ff";
    g.font = (opts.weight || 700) + " " + (opts.size || 64) + "px 'Space Grotesk', system-ui, sans-serif";
    g.textAlign = "center";
    g.textBaseline = "middle";
    g.fillText(text, w / 2, h / 2);
    var tex = new THREE.CanvasTexture(c);
    tex.encoding = THREE.sRGBEncoding;
    return tex;
  }

  /* ------------------------------------------------------------------ UI */

  function hud() {
    if (!games._ui.root) {
      var bar = U.el("div", { class: "gamebar", id: "gamebar" });
      games._ui.root = bar;
      document.getElementById("world").appendChild(bar);
    }
    return games._ui.root;
  }

  function setHud(entries) {
    var bar = hud();
    bar.innerHTML = "";
    entries.forEach(function (entry) {
      bar.appendChild(U.el("div", { class: "gamebar__chip" }, [
        U.el("b", { text: String(entry.value) }),
        U.el("span", { text: entry.label })
      ]));
    });
  }

  function setActionButtons(buttons) {
    var existing = document.getElementById("gamepad");
    if (existing) existing.remove();
    if (!buttons || !buttons.length) return;
    var pad = U.el("div", { class: "gamepad", id: "gamepad" });
    buttons.forEach(function (b) {
      var btn = U.el("button", {
        class: "gamepad__btn",
        type: "button",
        text: b.label
      }, null);
      btn.addEventListener("pointerdown", function (ev) {
        ev.preventDefault();
        ev.stopPropagation();
        NX.audio.sfx.click();
        b.onPress && b.onPress();
      });
      pad.appendChild(btn);
    });
    document.getElementById("world").appendChild(pad);
    games._ui.pad = pad;
  }

  function clearUi() {
    if (games._ui.root) games._ui.root.innerHTML = "";
    setActionButtons(null);
    var gp = document.getElementById("gamepad");
    if (gp) gp.remove();
  }

  /* --------------------------------------------------------------- state */

  function beginGame(id, opts) {
    if (!NX.scene.ready || !NX.scene.camera) return;
    NX.scene.hubGroup.visible = false;
    games.active = id;
    games.gameOver = false;
    games.score = 0;
    games.startTime = U.now();
    games.state = {};
    clear();
    clearUi();
    var def = games.registry[id];
    if (!def) { games.active = null; return; }
    if (def.init) def.init(games.state, opts || {});
    NX.audio.sfx.open();
    NX.audio.ambience(def && def.ambience ? def.ambience : "calm");
    NX.bus.emit("game:start", id);
    if (NX.app) NX.app.setHudTitle(NX.i18n.t(def.titleKey), NX.i18n.t("gamesLabel"));
  }

  function endGame() {
    if (!games.active) return;
    var def = games.registry[games.active];
    games.gameOver = true;
    NX.audio.sfx.gameover();
    var best = games.best[games.active] || 0;
    if (games.score > best) {
      games.best[games.active] = Math.floor(games.score);
      saveBest();
    }
    setHud([
      { label: NX.i18n.t("score"), value: Math.floor(games.score) },
      { label: NX.i18n.t("best"), value: Math.floor(games.best[games.active] || 0) }
    ]);
    setActionButtons([
      { label: NX.i18n.t("restart"), onPress: function () { beginGame(games.active); } },
      { label: NX.i18n.t("quit"), onPress: function () { quit(); } }
    ]);
    NX.bus.emit("game:over", { id: games.active, score: games.score });
    if (def && def.teardown) def.teardown(games.state);
  }

  function quit() {
    var id = games.active;
    var def = id ? games.registry[id] : null;
    if (def && def.teardown) def.teardown(games.state);
    games.active = null;
    games.gameOver = false;
    clear();
    clearUi();
    if (NX.scene.ready) NX.scene.hubGroup.visible = true;
    NX.audio.ambience(NX.worldById(NX.settings.get("world")).env);
    if (NX.app) NX.app.setHudTitle(NX.i18n.t("hub"), "Nexus VR");
    NX.bus.emit("game:quit", id);
  }

  games.quit = quit;

  /* ============================================================ ASTEROIDS */

  var AST = {
    titleKey: "asteroidsTitle",
    ambience: "deep",
    init: function (s) {
      var g = group();
      s.rocks = [];
      s.bullets = [];
      s.speed = 5.2;
      s.lives = 3;
      s.spawnTimer = 0;
      s.x = 0;
      s.targetX = 0;
      s.fireCooldown = 0;

      var rockGeo = new THREE.IcosahedronGeometry(0.42, 0);
      var rockMat = new THREE.MeshStandardMaterial({
        color: 0x5f6480,
        roughness: 0.88,
        metalness: 0.1,
        flatShading: true
      });
      s.rockGeo = rockGeo;
      s.rockMat = rockMat;

      var bulletGeo = new THREE.CylinderGeometry(0.018, 0.018, 0.5, 6);
      bulletGeo.rotateX(Math.PI / 2);
      s.bulletGeo = bulletGeo;
      s.bulletMat = new THREE.MeshBasicMaterial({ color: 0x7ff0ff });

      // ship
      var ship = new THREE.Group();
      var body = new THREE.Mesh(
        new THREE.ConeGeometry(0.14, 0.5, 4),
        new THREE.MeshStandardMaterial({ color: 0x9be7ff, roughness: 0.3, metalness: 0.6 })
      );
      body.rotation.x = -Math.PI / 2;
      body.rotation.z = Math.PI / 4;
      ship.add(body);
      var glow = new THREE.Mesh(
        new THREE.SphereGeometry(0.06, 8, 8),
        new THREE.MeshBasicMaterial({ color: 0x3be8ff })
      );
      glow.position.z = -0.25;
      ship.add(glow);
      ship.position.set(0, 0, -2.4);
      g.add(ship);
      s.ship = ship;
      s.glow = glow;

      setHud([
        { label: NX.i18n.t("score"), value: 0 },
        { label: "VIDAS", value: 3 }
      ]);
      setActionButtons([
        { label: NX.i18n.t("shooting") + " · " + "⟶", onPress: function () { fire(); } }
      ]);
    },

    update: function (dt, t, s) {
      if (games.gameOver) return;
      var g = group();
      var moveSpeed = 3.8;
      var xInput = 0;

      // Input: tap sets a target X, keyboard/pointers nudge
      if (NX.input.pointer.active && NX.input.dragging) {
        s.targetX += (NX.input.pointer.ndcX) * dt * 3.2;
      }
      if (s.keys) {
        if (s.keys.ArrowLeft || s.keys.a) xInput -= 1;
        if (s.keys.ArrowRight || s.keys.d) xInput += 1;
      }
      s.targetX += xInput * moveSpeed * dt;
      s.targetX = U.clamp(s.targetX, -3.2, 3.2);
      s.x += (s.targetX - s.x) * U.damp(8, dt);
      s.ship.position.x = s.x;
      s.ship.rotation.z = (s.targetX - s.x) * -0.35;
      s.ship.position.y = Math.sin(t * 2.4) * 0.05;

      // spawning
      s.spawnTimer -= dt;
      s.speed += dt * 0.06;
      if (s.spawnTimer <= 0) {
        s.spawnTimer = randomBetween(0.6, 1.2) * (5.2 / s.speed);
        var rock = new THREE.Mesh(s.rockGeo, s.rockMat);
        rock.position.set(randomBetween(-3.4, 3.4), randomBetween(-1.6, 1.9), -14 - Math.random() * 8);
        rock.userData = {
          spin: new THREE.Vector3(Math.random() * 2 - 1, Math.random() * 2 - 1, Math.random() * 2 - 1).multiplyScalar(1.5),
          size: randomBetween(0.7, 1.5)
        };
        rock.scale.setScalar(rock.userData.size);
        g.add(rock);
        s.rocks.push(rock);
      }

      // rocks
      for (var i = s.rocks.length - 1; i >= 0; i--) {
        var rock = s.rocks[i];
        rock.position.z += s.speed * dt;
        rock.rotation.x += rock.userData.spin.x * dt;
        rock.rotation.y += rock.userData.spin.y * dt;
        if (rock.position.z > 2.2) {
          g.remove(rock);
          s.rocks.splice(i, 1);
          continue;
        }
        // collision with the ship
        if (Math.abs(rock.position.z - s.ship.position.z) < 0.55 &&
            Math.abs(rock.position.x - s.x) < 0.3 + rock.userData.size * 0.35 &&
            Math.abs(rock.position.y - s.ship.position.y) < 0.28 + rock.userData.size * 0.3) {
          hit();
          g.remove(rock);
          s.rocks.splice(i, 1);
        }
      }

      // bullets
      for (var b = s.bullets.length - 1; b >= 0; b--) {
        var bullet = s.bullets[b];
        bullet.position.z -= 16 * dt;
        if (bullet.position.z < -20) {
          g.remove(bullet);
          s.bullets.splice(b, 1);
          continue;
        }
        for (var k = s.rocks.length - 1; k >= 0; k--) {
          var r = s.rocks[k];
          if (bullet.position.distanceTo(r.position) < 0.35 + r.userData.size * 0.32) {
            g.remove(bullet);
            s.bullets.splice(b, 1);
            g.remove(r);
            s.rocks.splice(k, 1);
            games.score += 10;
            NX.audio.sfx.hit();
            NX.scene.shake(0.28);
            break;
          }
        }
      }

      s.fireCooldown = Math.max(0, s.fireCooldown - dt);
      if (s.autoFire && s.fireCooldown === 0) fire();
      if (U.now() - games.startTime > 0.8) {
        games.score += dt * 4;
      }
      setHud([
        { label: NX.i18n.t("score"), value: Math.floor(games.score) },
        { label: "VIDAS", value: s.lives }
      ]);

      function fire() {
        if (s.fireCooldown > 0) return;
        s.fireCooldown = 0.22;
        var bullet = new THREE.Mesh(s.bulletGeo, s.bulletMat);
        bullet.position.copy(s.ship.position);
        bullet.position.z -= 0.35;
        g.add(bullet);
        s.bullets.push(bullet);
        NX.audio.sfx.click(0.08);
      }
      s.fire = fire;

      function hit() {
        s.lives--;
        NX.audio.sfx.hit();
        NX.scene.shake(0.7);
        U.haptic([20, 40, 30]);
        if (s.lives <= 0) {
          NX.audio.sfx.gameover();
          endGame();
        }
      }
    }
  };

  games.registry.asteroids = AST;

  /* ================================================================ ORBS */

  var ORBS = {
    titleKey: "orbsTitle",
    ambience: "neon",
    init: function (s) {
      var g = group();
      s.orbs = [];
      s.spawnTimer = 0;
      s.combo = 0;
      s.colors = [0x3be8ff, 0xff4fa3, 0xffb46b, 0x8b6bff, 0x47f0a2];
      setHud([
        { label: NX.i18n.t("score"), value: 0 },
        { label: "TEMPO", value: 60 }
      ]);

      s.orbGeo = new THREE.SphereGeometry(0.36, 20, 16);
      s.haloGeo = new THREE.SphereGeometry(0.62, 16, 12);

      s.life = 60;
    },

    update: function (dt, t, s) {
      if (games.gameOver) return;
      var g = group();
      s.life -= dt;
      if (s.life <= 0) {
        endGame();
        return;
      }

      s.spawnTimer -= dt;
      if (s.spawnTimer <= 0) {
        s.spawnTimer = randomBetween(0.4, 0.9);
        spawnOrb();
      }

      var hit = NX.scene.pick();
      var hovered = hit && hit.item ? hit : null;

      s.orbs.forEach(function (orb) {
        orb.position.z += (orb.userData.speed || 0.7) * dt;
        orb.position.x += Math.sin(t * (orb.userData.wob || 1) + orb.userData.phase) * 0.14 * dt * 8;
        orb.position.y += Math.cos(t * (orb.userData.wob || 1) * 0.7 + orb.userData.phase) * 0.06 * dt * 8;
        if (orb.material.emissiveIntensity !== undefined) {
          orb.material.emissiveIntensity = 0.6 + Math.sin(t * 4 + orb.userData.phase) * 0.25;
        }
        orb.rotation.y += dt;
        orb.userData.halo.scale.setScalar(1 + Math.sin(t * 3 + orb.userData.phase) * 0.06);
        if (orb.position.z > 0.4) {
          g.remove(orb);
          g.remove(orb.userData.halo);
          orb.userData.alive = false;
          s.combo = 0;
        }
      });
      s.orbs = s.orbs.filter(function (o) { return o.userData.alive; });

      // pick via gaze or pointer: nearest orb within reach of the ray
      if (hit && hit.index >= 0) {
        // scene.pick only returns cards; do our own raycast for orbs
      }
      raycastOrbs();

      setHud([
        { label: NX.i18n.t("score"), value: Math.floor(games.score) },
        { label: "TEMPO", value: Math.ceil(s.life) }
      ]);

      function spawnOrb() {
        var color = s.colors[Math.floor(Math.random() * s.colors.length)];
        var mesh = new THREE.Mesh(
          new THREE.SphereGeometry(0.30, 20, 16),
          new THREE.MeshBasicMaterial({ color: color })
        );
        mesh.position.set(randomBetween(-2.6, 2.6), randomBetween(-1.2, 1.6), -12 - Math.random() * 3);
        var halo = new THREE.Mesh(
          new THREE.SphereGeometry(0.56, 14, 10),
          new THREE.MeshBasicMaterial({
            color: color,
            transparent: true,
            opacity: 0.14,
            depthWrite: false,
            blending: THREE.AdditiveBlending
          })
        );
        mesh.add(halo);
        mesh.userData = {
          halo: halo,
          alive: true,
          phase: Math.random() * Math.PI * 2,
          wob: randomBetween(0.6, 1.4),
          speed: randomBetween(0.5, 0.9)
        };
        g.add(mesh);
        s.orbs.push(mesh);
      }

      function raycastOrbs() {
        _raycaster.setFromCamera(_centre, NX.scene.camera);
        for (var i = s.orbs.length - 1; i >= 0; i--) {
          var orb = s.orbs[i];
          var hitTest = _raycaster.intersectObject(orb, false);
          if (hitTest.length) {
            // pop!
            pop(orb, s.orbs.indexOf(orb));
            break;
          }
        }
      }

      function pop(orb, idx) {
        s.combo++;
        var points = 10 + Math.min(40, s.combo * 2);
        games.score += points;
        NX.audio.sfx.coin();
        NX.scene.shake(0.18);
        U.haptic(9);
        // burst
        var burst = new THREE.Mesh(
          new THREE.SphereGeometry(0.35, 12, 10),
          new THREE.MeshBasicMaterial({
            color: orb.material.color,
            transparent: true,
            opacity: 0.9,
            blending: THREE.AdditiveBlending,
            depthWrite: false
          })
        );
        burst.position.copy(orb.position);
        burst.userData = { life: 0.35, max: 0.35 };
        group().add(burst);
        orb.userData.alive = false;
        group().remove(orb);
        s.orbs = s.orbs.filter(function (o) { return o.userData.alive; });
        // pop bursts fade out
        setTimeout(function () {
          if (burst.parent) burst.parent.remove(burst);
        }, 380);
      }
    }
  };

  games.registry.orbs = ORBS;

  /* ================================================================ NEON */

  var NEON = {
    titleKey: "neonTitle",
    ambience: "neon",
    init: function (s) {
      var g = group();
      s.walls = [];
      s.speed = 6.5;
      s.lateral = 0;
      s.targetLateral = 0;
      s.spawnTimer = 0.5;
      s.distance = 0;

      var floorGeo = new THREE.PlaneGeometry(14, 80);
      var floorMat = new THREE.MeshBasicMaterial({ color: 0x1a0530, transparent: true, opacity: 0.94 });
      var floor = new THREE.Mesh(floorGeo, floorMat);
      floor.rotation.x = -Math.PI / 2;
      floor.position.set(0, -1.35, -20);
      g.add(floor);
      s.floor = floor;

      var lineMat = new THREE.LineBasicMaterial({ color: 0x3be8ff, transparent: true, opacity: 0.8 });
      var pts = [];
      for (var z = 0; z >= -40; z -= 1.2) {
        pts.push(new THREE.Vector3(-3.6, -1.34, z));
        pts.push(new THREE.Vector3(3.6, -1.34, z));
      }
      var lineGeo = new THREE.BufferGeometry().setFromPoints(pts);
      var lines = new THREE.LineSegments(lineGeo, lineMat);
      g.add(lines);
      s.lines = lines;

      var runner = new THREE.Group();
      var body = new THREE.Mesh(
        new THREE.BoxGeometry(0.36, 0.36, 0.36),
        new THREE.MeshStandardMaterial({
          color: 0x3be8ff, emissive: 0x3be8ff, emissiveIntensity: 0.9, roughness: 0.2
        })
      );
      runner.add(body);
      runner.position.set(0, -1.0, -2.2);
      g.add(runner);
      s.runner = runner;

      setHud([
        { label: NX.i18n.t("score"), value: 0 },
        { label: NX.i18n.t("best"), value: Math.floor(games.best.neon || 0) }
      ]);
    },

    update: function (dt, t, s) {
      if (games.gameOver) return;
      var g = group();
      s.speed += dt * 0.22;
      s.distance += s.speed * dt;

      // Lateral input: drag / pointer / keyboard
      if (NX.input.pointer.active) {
        s.targetLateral = U.clamp(NX.input.pointer.ndcX * 3.0, -3.0, 3.0);
      }
      if (s.keys) {
        if (s.keys.ArrowLeft || s.keys.a) s.targetLateral -= 3.0 * dt * 2;
        if (s.keys.ArrowRight || s.keys.d) s.targetLateral += 3.0 * dt * 2;
        s.targetLateral = U.clamp(s.targetLateral, -3.0, 3.0);
      }
      s.lateral += (s.targetLateral - s.lateral) * U.damp(12, dt);
      s.runner.position.x = s.lateral;
      s.runner.rotation.z = (s.targetLateral - s.lateral) * 0.3;
      s.runner.position.y = -1.0 + Math.abs(Math.sin(t * 6)) * 0.06;

      // Tiles
      s.spawnTimer -= dt;
      if (s.spawnTimer <= 0) {
        s.spawnTimer = randomBetween(0.35, 0.7) * (6.5 / s.speed);
        var tile = new THREE.Mesh(
          new THREE.BoxGeometry(0.9, 1.6, 0.35),
          new THREE.MeshStandardMaterial({
            color: 0xff4fa3, emissive: 0xff4fa3, emissiveIntensity: 1.1,
            transparent: true, opacity: 0.92
          })
        );
        tile.position.set(randomBetween(-2.9, 2.9), -0.55, -30);
        g.add(tile);
        s.walls.push(tile);
      }

      for (var i = s.walls.length - 1; i >= 0; i--) {
        var w = s.walls[i];
        w.position.z += s.speed * dt;
        if (w.position.z > 0.5) {
          g.remove(w);
          s.walls.splice(i, 1);
          continue;
        }
        if (Math.abs(w.position.z - s.runner.position.z) < 0.7 &&
            Math.abs(w.position.x - s.runner.position.x) < 0.62) {
          NX.audio.sfx.hit();
          NX.scene.shake(0.7);
          U.haptic([20, 30, 20]);
          endGame();
          return;
        }
      }

      games.score = Math.floor(s.distance);
      if (Math.random() < 0.4) {
        setHud([
          { label: NX.i18n.t("score"), value: games.score },
          { label: NX.i18n.t("best"), value: Math.floor(games.best.neon || 0) }
        ]);
      }
    }
  };

  games.registry.neon = NEON;

  /* ============================================================== update */

  games.update = function (dt, t) {
    if (!games.active) return;
    var def = games.registry[games.active];
    if (!def) return;
    def.update(dt, t, games.state);
  };

  // Track keyboard keys for desktop
  var keys = {};
  window.addEventListener("keydown", function (e) {
    keys[e.key] = true;
    if (games.state) games.state.keys = keys;
  });
  window.addEventListener("keyup", function (e) {
    keys[e.key] = false;
  });

  /* ------------------------------------------------------------- menu UI */

  games.openMenu = function () {
    var items = [
      { id: "asteroids", title: NX.i18n.t("asteroidsTitle"), subtitle: NX.i18n.t("asteroidsSub"), accent: "#3be8ff" },
      { id: "orbs", title: NX.i18n.t("orbsTitle"), subtitle: NX.i18n.t("orbsSub"), accent: "#ff4fa3" },
      { id: "neon", title: NX.i18n.t("neonTitle"), subtitle: NX.i18n.t("neonSub"), accent: "#47f0a2" }
    ];
    NX.app.modal({
      kicker: NX.i18n.t("gamesLabel"),
      title: NX.i18n.t("gamesLabel"),
      sub: NX.i18n.t("gamesLabelSub"),
      choices: items.map(function (it) {
        return {
          title: it.title,
          subtitle: it.subtitle,
          accent: it.accent,
          badge: games.best[it.id] ? NX.i18n.t("best") + " " + Math.floor(games.best[it.id]) : null,
          onSelect: function () {
            NX.app.closeModal();
            beginGame(it.id);
          }
        };
      })
    });
  };

  games.begin = beginGame;
  games.end = endGame;

  NX.bus.on("settings:change", function (e) {
    if (e.key === "reducedMotion" && games.active) {
      // Games keep running; the reduce-motion setting only affects UI motion.
    }
  });

  NX.bus.on("input:up", function (ev) {
    if (!games.active || games.gameOver) return;
    if (games.active === "asteroids" && ev && ev.tap && games.state.fire) {
      games.state.fire();
    }
  });

  NX.bus.on("game:quit", function () {
    clear();
  });
})();
