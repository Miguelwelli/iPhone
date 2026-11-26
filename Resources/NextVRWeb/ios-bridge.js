// Native iOS AR Camera + Apple Vision Hand-Tracking + CoreMotion Bridge for Next VR.
// Works 100% offline inside the native NextVR.app WKWebView, with automatic Web/MediaPipe fallback.

let nativeHandsActive = false;
let stream = null;
let video = null;
let landmarker = null;
let rafId = 0;
let lastVideoTime = -1;
let visionModule = null;

const hasNativeBridge = () =>
  !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nextvrNative);

function postNative(action, payload = {}) {
  if (!hasNativeBridge()) return false;
  try {
    window.webkit.messageHandlers.nextvrNative.postMessage({ action, ...payload });
    return true;
  } catch {
    return false;
  }
}

function getCurrentEnv() {
  try {
    return JSON.parse(localStorage.getItem("nextvr.v1") || "{}").env || "sunset";
  } catch {
    return "sunset";
  }
}

let lastEnvSent = null;
function syncCameraEnvironment() {
  const env = getCurrentEnv();
  const isPass = env === "passthrough";
  if (hasNativeBridge()) {
    const active = isPass || nativeHandsActive;
    document.documentElement.dataset.nextvrCamera = isPass ? "on" : "off";
    if (lastEnvSent !== `${env}:${active}`) {
      lastEnvSent = `${env}:${active}`;
      postNative("setEnvironment", { env, passthrough: isPass, handsActive: nativeHandsActive });
    }
    return;
  }
  document.documentElement.dataset.nextvrCamera = stream && isPass ? "on" : "off";
}

// Hand skeleton drawing on #overlay for visual feedback on iPhone
const HAND_CONNECTIONS = [
  [0,1],[1,2],[2,3],[3,4],
  [0,5],[5,6],[6,7],[7,8],
  [5,9],[9,10],[10,11],[11,12],
  [9,13],[13,14],[14,15],[15,16],
  [13,17],[17,18],[18,19],[19,20],[0,17]
];

function drawHandOverlay(hands) {
  const canvas = document.getElementById("overlay");
  if (!canvas) return;
  const w = window.innerWidth;
  const h = window.innerHeight;
  if (canvas.width !== w || canvas.height !== h) {
    canvas.width = w;
    canvas.height = h;
  }
  const ctx = canvas.getContext("2d");
  if (!ctx) return;
  ctx.clearRect(0, 0, w, h);

  let handDraw = 1;
  try {
    const saved = JSON.parse(localStorage.getItem("nextvr.v1") || "{}");
    if (saved.handDraw !== undefined) handDraw = saved.handDraw;
  } catch {}
  if (!handDraw || window.__gorillaStereoOverlay || !hands || !hands.length) return;

  for (const hand of hands) {
    const pts = hand.lm;
    if (!pts || pts.length < 21) continue;
    const pinching = !!hand.pinching;

    ctx.save();
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.lineWidth = 2.6;
    ctx.strokeStyle = pinching ? "rgba(103, 232, 249, 0.92)" : "rgba(167, 139, 250, 0.78)";
    ctx.shadowColor = pinching ? "rgba(103, 232, 249, 0.65)" : "rgba(124, 107, 255, 0.55)";
    ctx.shadowBlur = 10;

    ctx.beginPath();
    for (const [a, b] of HAND_CONNECTIONS) {
      const pa = pts[a];
      const pb = pts[b];
      if (!pa || !pb) continue;
      ctx.moveTo(pa.x * w, pa.y * h);
      ctx.lineTo(pb.x * w, pb.y * h);
    }
    ctx.stroke();

    for (let i = 0; i < 21; i++) {
      const p = pts[i];
      if (!p) continue;
      const isTip = i === 4 || i === 8;
      ctx.beginPath();
      ctx.arc(p.x * w, p.y * h, isTip ? (pinching ? 6.5 : 5) : 3, 0, Math.PI * 2);
      ctx.fillStyle = isTip
        ? (pinching ? "#67e8f9" : "#ffffff")
        : "rgba(242, 244, 248, 0.88)";
      ctx.fill();
    }
    ctx.restore();
  }
}

// Called from Swift (AVCaptureSession + Apple Vision VNDetectHumanHandPoseRequest)
window.__iosReceiveNativeHands = function (payload) {
  if (!nativeHandsActive || !payload) return;
  const hands = payload.hands || [];
  drawHandOverlay(hands);
  if (typeof window.nextvrHands === "function") {
    window.nextvrHands({
      hands,
      validForMs: payload.validForMs || 380,
      timestampNs: payload.timestampNs || Math.round(performance.now() * 1e6)
    });
  }
};

// Intercept brightness changes from Quick Settings if running inside native iOS shell
document.addEventListener("input", (e) => {
  const target = e.target;
  if (!target || !hasNativeBridge()) return;
  if (target.dataset?.qRange === "brightness" || target.getAttribute?.("aria-label") === "Brilho") {
    const val = Number(target.value);
    if (Number.isFinite(val)) {
      postNative("setBrightness", { percent: val });
    }
  }
}, { passive: true });

// Intercept click sounds / subtle haptics on primary VR buttons
document.addEventListener("click", (e) => {
  if (!hasNativeBridge()) return;
  const btn = e.target instanceof Element ? e.target.closest("button,[role='button']") : null;
  if (btn) postNative("hapticTap");
}, { passive: true, capture: true });

// Fallback MediaPipe implementation (if opened outside native app)
const MODEL_URL = "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task";
const WASM_URL = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm";
const MODULE_URL = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14";

function distance(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y, (a.z || 0) - (b.z || 0));
}

async function loadLandmarker() {
  if (landmarker) return landmarker;
  if (!visionModule) visionModule = await import(MODULE_URL);
  const vision = await visionModule.FilesetResolver.forVisionTasks(WASM_URL);
  const options = {
    baseOptions: { modelAssetPath: MODEL_URL, delegate: "GPU" },
    runningMode: "VIDEO",
    numHands: 2,
    minHandDetectionConfidence: 0.55,
    minHandPresenceConfidence: 0.5,
    minTrackingConfidence: 0.5
  };
  try {
    landmarker = await visionModule.HandLandmarker.createFromOptions(vision, options);
  } catch {
    options.baseOptions.delegate = "CPU";
    landmarker = await visionModule.HandLandmarker.createFromOptions(vision, options);
  }
  return landmarker;
}

function buildHandStruct(points, index, handednessLabel) {
  const thumb = points[4];
  const indexTip = points[8];
  const palmWidth = distance(points[5], points[17]);
  const pinching = distance(thumb, indexTip) < Math.max(0.038, palmWidth * 0.44);
  const wrist = points[0];
  const fist =
    distance(wrist, points[8]) < distance(wrist, points[6]) * 1.12 &&
    distance(wrist, points[12]) < distance(wrist, points[10]) * 1.12 &&
    distance(wrist, points[16]) < distance(wrist, points[14]) * 1.12 &&
    distance(wrist, points[20]) < distance(wrist, points[18]) * 1.14;

  const flatPoints = new Array(63);
  for (let i = 0; i < 21; i++) {
    const p = points[i] || { x: 0.5, y: 0.5, z: 0 };
    flatPoints[i * 3] = p.x;
    flatPoints[i * 3 + 1] = p.y;
    flatPoints[i * 3 + 2] = p.z || 0;
  }

  const isLeft = handednessLabel ? handednessLabel.toLowerCase().includes("left") : points[9].x < 0.5;
  const x = indexTip.x;
  const y = indexTip.y;

  return {
    id: isLeft ? "left" : (index === 0 ? "right" : `hand_${index}`),
    left: isLeft,
    handedness: isLeft ? "Left" : "Right",
    physicalSide: isLeft ? "left" : "right",
    pinching,
    fist,
    palmWidth,
    palm: [points[9].x, points[9].y],
    aim: [(x - 0.5) * 2.1795, (0.5 - y) * 1.453],
    points: flatPoints,
    lm: points.map(p => ({ x: p.x, y: p.y, z: p.z || 0 }))
  };
}

function processWebFrame() {
  if (!stream || !video || !landmarker) return;
  if (video.readyState >= 2 && video.currentTime !== lastVideoTime) {
    lastVideoTime = video.currentTime;
    try {
      const result = landmarker.detectForVideo(video, performance.now());
      const landmarks = result.landmarks || [];
      const handednesses = result.handednesses || [];
      const hands = landmarks.map((pts, idx) =>
        buildHandStruct(pts, idx, handednesses[idx]?.[0]?.categoryName || "")
      );
      drawHandOverlay(hands);
      if (typeof window.nextvrHands === "function") {
        window.nextvrHands({
          hands,
          validForMs: 350,
          timestampNs: Math.round(performance.now() * 1e6)
        });
      }
    } catch {}
  }
  syncCameraEnvironment();
  rafId = requestAnimationFrame(processWebFrame);
}

window.nextvrStartHands = async function () {
  if (hasNativeBridge()) {
    nativeHandsActive = true;
    postNative("startHands");
    syncCameraEnvironment();
    return true;
  }
  if (!navigator.mediaDevices?.getUserMedia) return false;
  if (stream && landmarker) return true;
  try {
    stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: { facingMode: { ideal: "environment" }, width: { ideal: 640 }, height: { ideal: 480 } }
    });
    video = document.getElementById("ios-camera-passthrough");
    video.srcObject = stream;
    await video.play();
    await loadLandmarker();
    syncCameraEnvironment();
    cancelAnimationFrame(rafId);
    rafId = requestAnimationFrame(processWebFrame);
    return true;
  } catch {
    if (stream) stream.getTracks().forEach(t => t.stop());
    stream = null;
    syncCameraEnvironment();
    return false;
  }
};

window.nextvrStopHands = function () {
  if (hasNativeBridge()) {
    nativeHandsActive = false;
    drawHandOverlay([]);
    postNative("stopHands");
    syncCameraEnvironment();
    return;
  }
  cancelAnimationFrame(rafId);
  rafId = 0;
  if (stream) stream.getTracks().forEach(t => t.stop());
  stream = null;
  if (video) video.srcObject = null;
  if (landmarker) { landmarker.close(); landmarker = null; }
  drawHandOverlay([]);
  syncCameraEnvironment();
};

window.addEventListener("storage", syncCameraEnvironment);
setInterval(syncCameraEnvironment, 450);
syncCameraEnvironment();
postNative("ready");
