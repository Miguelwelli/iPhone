import AVFoundation
import CoreMotion
import SwiftUI
import UIKit
import Vision
import WebKit

@main
struct NextVRApp: App {
    init() {
        configureAudioSession()
        UIApplication.shared.isIdleTimerDisabled = true
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    var body: some Scene {
        WindowGroup {
            NextVRRootView()
                .ignoresSafeArea()
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}

struct NextVRRootView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> NextVRViewController {
        NextVRViewController()
    }

    func updateUIViewController(_ uiViewController: NextVRViewController, context: Context) {}
}

// Custom local scheme so fetch() for gorilla-map.task / gorilla-rig.task, ES modules and Origin headers work cleanly on iOS
final class NextVRSchemeHandler: NSObject, WKURLSchemeHandler {
    private let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        var relPath = requestURL.path
        while relPath.hasPrefix("/") {
            relPath.removeFirst()
        }
        if relPath.isEmpty {
            relPath = "index.html"
        }

        let targetURL = rootURL.appendingPathComponent(relPath).standardizedFileURL
        guard targetURL.path.hasPrefix(rootURL.path),
              FileManager.default.fileExists(atPath: targetURL.path),
              let data = try? Data(contentsOf: targetURL) else {
            let notFound = HTTPURLResponse(
                url: requestURL,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: ["Access-Control-Allow-Origin": "*"]
            )!
            urlSchemeTask.didReceive(notFound)
            urlSchemeTask.didFinish()
            return
        }

        let mime = Self.mimeType(for: targetURL.pathExtension.lowercased())
        let response = HTTPURLResponse(
            url: requestURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mime,
                "Content-Length": "\(data.count)",
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "no-cache"
            ]
        )!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    private static func mimeType(for ext: String) -> String {
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg": return "image/svg+xml"
        case "woff2": return "font/woff2"
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        case "task", "glb", "bin": return "application/octet-stream"
        default: return "application/octet-stream"
        }
    }
}

@MainActor
final class NextVRViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    private var cameraContainerView: UIView!
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var webView: WKWebView!
    private let motionManager = CMMotionManager()
    private let handPipeline = CameraHandPipeline()
    private var batteryTimer: Timer?
    private var isPassthroughVisible = false
    private var isHandsRequested = false
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 5.0 / 255.0, green: 7.0 / 255.0, blue: 12.0 / 255.0, alpha: 1.0)

        setupCameraBackgroundView()
        setupWebView()
        setupHandPipelineCallbacks()
        startNativeGyroBridge()
        startBatteryBridge()
        loadNextVR()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = cameraContainerView.bounds
        updatePreviewOrientation()
    }

    private func setupCameraBackgroundView() {
        cameraContainerView = UIView(frame: view.bounds)
        cameraContainerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cameraContainerView.backgroundColor = .black
        cameraContainerView.isHidden = true
        view.addSubview(cameraContainerView)

        let layer = AVCaptureVideoPreviewLayer(session: handPipeline.session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = cameraContainerView.bounds
        cameraContainerView.layer.addSublayer(layer)
        previewLayer = layer
    }

    private func updatePreviewOrientation() {
        guard let connection = previewLayer?.connection else { return }
        let sceneOrientation = view.window?.windowScene?.interfaceOrientation ?? .landscapeRight
        let angle: CGFloat
        switch sceneOrientation {
        case .landscapeRight: angle = 0
        case .landscapeLeft: angle = 180
        case .portraitUpsideDown: angle = 270
        default: angle = 90
        }
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        handPipeline.updateInterfaceOrientation(sceneOrientation)
    }

    private func setupWebView() {
        let contentController = WKUserContentController()
        contentController.add(WeakScriptMessageHandler(delegate: self), name: "nextvrNative")

        // Override DeviceOrientationEvent.requestPermission so gyro works seamlessly without Safari HTTPS restriction
        let polyfillJS = """
        (function() {
          if (typeof DeviceOrientationEvent !== 'undefined') {
            DeviceOrientationEvent.requestPermission = async function() { return 'granted'; };
          }
          if (typeof DeviceMotionEvent !== 'undefined') {
            DeviceMotionEvent.requestPermission = async function() { return 'granted'; };
          }
        })();
        """
        let userScript = WKUserScript(source: polyfillJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        contentController.addUserScript(userScript)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        if let webRootURL = Bundle.main.url(forResource: "NextVRWeb", withExtension: nil) {
            configuration.setURLSchemeHandler(NextVRSchemeHandler(rootURL: webRootURL), forURLScheme: "nextvr")
        }

        webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = self
        webView.uiDelegate = self

        view.addSubview(webView)
    }

    private func loadNextVR() {
        guard Bundle.main.url(forResource: "NextVRWeb", withExtension: nil) != nil,
              let url = URL(string: "nextvr://app.local/index.html") else {
            return
        }
        webView.load(URLRequest(url: url))
    }

    // MARK: - CoreMotion Gyroscope -> DOM DeviceOrientationEvent

    private func startNativeGyroBridge() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let q = motion.attitude.quaternion
            // Convert CoreMotion quaternion (Z-up ENU-like frame) to W3C DeviceOrientation Euler angles (alpha, beta, gamma in degrees)
            let (alpha, beta, gamma) = Self.quaternionToW3CEulerDegrees(x: q.x, y: q.y, z: q.z, w: q.w)
            let orientAngle = self.currentWindowOrientationAngle()
            let js = String(
                format: """
                (function(){
                  window.orientation = %d;
                  var ev;
                  try {
                    ev = new DeviceOrientationEvent('deviceorientation', { alpha: %.4f, beta: %.4f, gamma: %.4f, absolute: false });
                  } catch (e) {
                    ev = new Event('deviceorientation');
                    ev.alpha = %.4f; ev.beta = %.4f; ev.gamma = %.4f;
                  }
                  window.dispatchEvent(ev);
                })();
                """,
                orientAngle, alpha, beta, gamma, alpha, beta, gamma
            )
            self.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    private func currentWindowOrientationAngle() -> Int {
        let sceneOrientation = view.window?.windowScene?.interfaceOrientation ?? .landscapeRight
        switch sceneOrientation {
        case .landscapeRight: return 90
        case .landscapeLeft: return -90
        case .portraitUpsideDown: return 180
        default: return 0
        }
    }

    private static func quaternionToW3CEulerDegrees(x: Double, y: Double, z: Double, w: Double) -> (Double, Double, Double) {
        // W3C DeviceOrientation uses intrinsic Z-X'-Y'' rotation order: R = Rz(alpha) * Rx(beta) * Ry(gamma)
        let r11 = 1.0 - 2.0 * (y * y + z * z)
        let r12 = 2.0 * (x * y - z * w)
        let r13 = 2.0 * (x * z + y * w)
        let r21 = 2.0 * (x * y + z * w)
        let r22 = 1.0 - 2.0 * (x * x + z * z)
        let r23 = 2.0 * (y * z - x * w)
        let r31 = 2.0 * (x * z - y * w)
        let r32 = 2.0 * (y * z + x * w)
        let r33 = 1.0 - 2.0 * (x * x + y * y)

        let radToDeg = 180.0 / Double.pi
        var alpha: Double = 0
        var beta: Double = 0
        var gamma: Double = 0

        if abs(r32) < 0.9999 {
            beta = asin(max(-1.0, min(1.0, r32)))
            alpha = atan2(-r12, r22)
            gamma = atan2(-r31, r33)
        } else {
            beta = r32 > 0 ? (Double.pi / 2.0) : (-Double.pi / 2.0)
            alpha = atan2(r21, r11)
            gamma = 0
        }

        var alphaDeg = alpha * radToDeg
        if alphaDeg < 0 { alphaDeg += 360.0 }
        let betaDeg = beta * radToDeg
        let gammaDeg = gamma * radToDeg
        return (alphaDeg, betaDeg, gammaDeg)
    }

    // MARK: - Battery Bridge

    private func startBatteryBridge() {
        sendBatteryStatus()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendBatteryStatus()
            }
        }
    }

    private func sendBatteryStatus() {
        let level = UIDevice.current.batteryLevel >= 0 ? Double(UIDevice.current.batteryLevel) : 1.0
        let state = UIDevice.current.batteryState
        let charging = (state == .charging || state == .full)
        let js = String(
            format: "if (typeof window.nextvrBattery === 'function') { window.nextvrBattery({ level: %.2f, charging: %@ }); }",
            level,
            charging ? "true" : "false"
        )
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Native Camera + Apple Vision Hand Tracking

    private func setupHandPipelineCallbacks() {
        handPipeline.onHandsJSON = { [weak self] jsonString in
            Task { @MainActor [weak self] in
                guard let self, self.isHandsRequested else { return }
                self.webView?.evaluateJavaScript("window.__iosReceiveNativeHands && window.__iosReceiveNativeHands(\(jsonString));", completionHandler: nil)
            }
        }
    }

    private func updateCameraSessionState() {
        cameraContainerView.isHidden = !isPassthroughVisible
        let shouldRunCamera = isPassthroughVisible || isHandsRequested
        handPipeline.setHandTrackingEnabled(isHandsRequested)
        if shouldRunCamera {
            updatePreviewOrientation()
            handPipeline.startIfAuthorized()
        } else {
            handPipeline.stop()
        }
    }

    // MARK: - WKScriptMessageHandler

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "nextvrNative",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        let passthrough = body["passthrough"] as? Bool
        let handsActive = body["handsActive"] as? Bool
        let brightnessPercent = body["percent"] as? Double

        Task { @MainActor [weak self] in
            guard let self else { return }
            switch action {
            case "ready":
                self.sendBatteryStatus()
            case "startHands":
                self.isHandsRequested = true
                self.updateCameraSessionState()
            case "stopHands":
                self.isHandsRequested = false
                self.updateCameraSessionState()
            case "setEnvironment":
                if let passthrough {
                    self.isPassthroughVisible = passthrough
                }
                if let handsActive {
                    self.isHandsRequested = handsActive
                }
                self.updateCameraSessionState()
            case "setBrightness":
                if let brightnessPercent {
                    let clamped = max(0.08, min(1.0, CGFloat(brightnessPercent / 100.0)))
                    UIScreen.main.brightness = clamped
                }
            case "hapticTap":
                self.hapticGenerator.impactOccurred(intensity: 0.45)
            default:
                break
            }
        }
    }

    // MARK: - WKUIDelegate & WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sendBatteryStatus()
    }

    @available(iOS 15.0, *)
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.grant)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            UIApplication.shared.open(url)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = UIAlertController(title: "Next VR", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler()
        })
        present(alert, animated: true)
    }
}

// MARK: - Apple Vision Hand Pose + AVCaptureSession Pipeline

final class CameraHandPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    var onHandsJSON: (@Sendable (String) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.miguelwelli.nextvr.camera", qos: .userInteractive)
    private let visionQueue = DispatchQueue(label: "com.miguelwelli.nextvr.vision", qos: .userInteractive)
    private let handRequest: VNDetectHumanHandPoseRequest = {
        let req = VNDetectHumanHandPoseRequest()
        req.maximumHandCount = 2
        return req
    }()

    private var isConfigured = false
    private var handTrackingEnabled = false
    private var isProcessingFrame = false
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var currentExifOrientation: CGImagePropertyOrientation = .up

    private static let jointOrder: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip
    ]

    func setHandTrackingEnabled(_ enabled: Bool) {
        visionQueue.async {
            self.handTrackingEnabled = enabled
        }
    }

    func updateInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        visionQueue.async {
            switch orientation {
            case .landscapeRight:
                self.currentExifOrientation = .up
            case .landscapeLeft:
                self.currentExifOrientation = .down
            case .portraitUpsideDown:
                self.currentExifOrientation = .left
            default:
                self.currentExifOrientation = .right
            }
        }
    }

    func startIfAuthorized() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.startSession()
                }
            }
        default:
            break
        }
    }

    private func startSession() {
        sessionQueue.async {
            if !self.isConfigured {
                self.configureSession()
            }
            if self.isConfigured && !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        guard let camera = discovery.devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.setSampleBufferDelegate(self, queue: visionQueue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        session.commitConfiguration()
        isConfigured = true
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard handTrackingEnabled, !isProcessingFrame else { return }
        let now = CACurrentMediaTime()
        if now - lastFrameTimestamp < 0.030 { return } // ~30 fps cap
        lastFrameTimestamp = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isProcessingFrame = true
        defer { isProcessingFrame = false }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: currentExifOrientation, options: [:])
        do {
            try handler.perform([handRequest])
            let observations = handRequest.results ?? []
            let json = buildHandsPayloadJSON(from: observations, timestampMs: now * 1000.0)
            onHandsJSON?(json)
        } catch {
            // Skip failed frame safely
        }
    }

    private func buildHandsPayloadJSON(
        from observations: [VNHumanHandPoseObservation],
        timestampMs: Double
    ) -> String {
        var handDicts: [[String: Any]] = []

        for (idx, obs) in observations.enumerated() {
            guard let recognized = try? obs.recognizedPoints(.all) else { continue }

            var pts: [(x: Double, y: Double)] = []
            pts.reserveCapacity(21)
            var validJoints = 0

            for jointName in Self.jointOrder {
                if let pt = recognized[jointName], pt.confidence > 0.15 {
                    // Vision normalized coordinates have origin at bottom-left; convert to top-left [0, 1]
                    pts.append((x: Double(pt.location.x), y: Double(1.0 - pt.location.y)))
                    validJoints += 1
                } else {
                    let fallback = pts.first ?? (x: 0.5, y: 0.5)
                    pts.append(fallback)
                }
            }

            if validJoints < 8 { continue }

            let wrist = pts[0]
            let thumbTip = pts[4]
            let indexMCP = pts[5]
            let indexPIP = pts[6]
            let indexTip = pts[8]
            let middleMCP = pts[9]
            let middlePIP = pts[10]
            let middleTip = pts[12]
            let ringPIP = pts[14]
            let ringTip = pts[16]
            let littleMCP = pts[17]
            let littlePIP = pts[18]
            let littleTip = pts[20]

            let palmWidth = hypot(indexMCP.x - littleMCP.x, indexMCP.y - littleMCP.y)
            let pinchDist = hypot(thumbTip.x - indexTip.x, thumbTip.y - indexTip.y)
            let pinching = pinchDist < max(0.040, palmWidth * 0.45)

            let fist =
                hypot(wrist.x - indexTip.x, wrist.y - indexTip.y) < hypot(wrist.x - indexPIP.x, wrist.y - indexPIP.y) * 1.12 &&
                hypot(wrist.x - middleTip.x, wrist.y - middleTip.y) < hypot(wrist.x - middlePIP.x, wrist.y - middlePIP.y) * 1.12 &&
                hypot(wrist.x - ringTip.x, wrist.y - ringTip.y) < hypot(wrist.x - ringPIP.x, wrist.y - ringPIP.y) * 1.12 &&
                hypot(wrist.x - littleTip.x, wrist.y - littleTip.y) < hypot(wrist.x - littlePIP.x, wrist.y - littlePIP.y) * 1.14

            let chiralityLeft: Bool
            if #available(iOS 15.0, *) {
                switch obs.chirality {
                case .left: chiralityLeft = true
                case .right: chiralityLeft = false
                default: chiralityLeft = middleMCP.x < 0.5
                }
            } else {
                chiralityLeft = middleMCP.x < 0.5
            }

            var flatPoints: [Double] = []
            flatPoints.reserveCapacity(63)
            var lmArray: [[String: Double]] = []
            lmArray.reserveCapacity(21)

            for p in pts {
                flatPoints.append(p.x)
                flatPoints.append(p.y)
                flatPoints.append(0.0)
                lmArray.append(["x": p.x, "y": p.y, "z": 0.0])
            }

            let aimX = (indexTip.x - 0.5) * 2.1795
            let aimY = (0.5 - indexTip.y) * 1.4530
            let handID = chiralityLeft ? "left" : (idx == 0 ? "right" : "right_\(idx)")

            handDicts.append([
                "id": handID,
                "left": chiralityLeft,
                "handedness": chiralityLeft ? "Left" : "Right",
                "physicalSide": chiralityLeft ? "left" : "right",
                "pinching": pinching,
                "fist": fist,
                "palmWidth": palmWidth,
                "palm": [middleMCP.x, middleMCP.y],
                "aim": [aimX, aimY],
                "points": flatPoints,
                "lm": lmArray
            ])
        }

        let payload: [String: Any] = [
            "hands": handDicts,
            "validForMs": 380,
            "timestampNs": Int64(timestampMs * 1_000_000)
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"hands\":[]}"
        }
        return str
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
