import ARKit
import AVFoundation
import CoreMotion
import PhotosUI
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
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}

struct NextVRRootView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> NextVRViewController {
        NextVRViewController()
    }

    func updateUIViewController(_ uiViewController: NextVRViewController, context: Context) {}
}

// High-speed asynchronous local scheme handler with RAM preloading & HTTP Range support
final class NextVRSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    private let rootURL: URL
    private let ioQueue = DispatchQueue(label: "com.miguelwelli.nextvr.asset-io", qos: .userInitiated, attributes: .concurrent)
    private let lock = NSLock()
    private var memoryCache: [String: Data] = [:]
    private var stoppedTasks = Set<ObjectIdentifier>()

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
        super.init()
        preloadCriticalAssets()
    }

    private func preloadCriticalAssets() {
        let root = self.rootURL
        ioQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            var preloaded: [String: Data] = [:]
            for case let fileURL as URL in enumerator {
                guard let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      vals.isRegularFile == true,
                      let size = vals.fileSize,
                      size <= 3_000_000 else { continue } // Preload all HTML/JS/CSS/Fonts/Icons/360° Panoramas into RAM
                let stdPath = fileURL.standardizedFileURL.path
                if let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) {
                    preloaded[stdPath] = data
                }
            }
            self.lock.lock()
            for (k, v) in preloaded {
                self.memoryCache[k] = v
            }
            self.lock.unlock()
        }
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let taskBox = UncheckedSendableBox(value: urlSchemeTask)
        let taskID = ObjectIdentifier(urlSchemeTask as AnyObject)
        guard let requestURL = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let rangeHeader = urlSchemeTask.request.value(forHTTPHeaderField: "Range")
        var relPath = requestURL.path
        while relPath.hasPrefix("/") {
            relPath.removeFirst()
        }
        if relPath.isEmpty {
            relPath = "index.html"
        }

        let targetURL = rootURL.appendingPathComponent(relPath).standardizedFileURL
        guard targetURL.path.hasPrefix(rootURL.path) else {
            finishWithNotFound(taskBox.value, taskID: taskID, url: requestURL)
            return
        }

        // Fast-path: check RAM cache immediately without disk I/O
        lock.lock()
        let cached = memoryCache[targetURL.path]
        lock.unlock()

        if let cached {
            serveData(cached, for: taskBox.value, taskID: taskID, requestURL: requestURL, ext: targetURL.pathExtension, rangeHeader: rangeHeader)
            return
        }

        // Background-queue memory-mapped read for large 3D GLB assets (gorilla-map.task) so main/UI thread never blocks
        ioQueue.async { [weak self] in
            guard let self else { return }
            if self.isStopped(taskID) { return }

            guard FileManager.default.fileExists(atPath: targetURL.path),
                  let data = try? Data(contentsOf: targetURL, options: .mappedIfSafe) else {
                self.finishWithNotFound(taskBox.value, taskID: taskID, url: requestURL)
                return
            }

            if data.count <= 3_000_000 {
                self.lock.lock()
                self.memoryCache[targetURL.path] = data
                self.lock.unlock()
            }

            self.serveData(data, for: taskBox.value, taskID: taskID, requestURL: requestURL, ext: targetURL.pathExtension, rangeHeader: rangeHeader)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask as AnyObject)
        lock.lock()
        stoppedTasks.insert(taskID)
        lock.unlock()
    }

    private func isStopped(_ taskID: ObjectIdentifier) -> Bool {
        lock.lock()
        let s = stoppedTasks.contains(taskID)
        lock.unlock()
        return s
    }

    private func clearStopped(_ taskID: ObjectIdentifier) {
        lock.lock()
        stoppedTasks.remove(taskID)
        lock.unlock()
    }

    private func finishWithNotFound(_ task: any WKURLSchemeTask, taskID: ObjectIdentifier, url: URL) {
        guard !isStopped(taskID) else {
            clearStopped(taskID)
            return
        }
        let resp = HTTPURLResponse(
            url: url,
            statusCode: 404,
            httpVersion: "HTTP/1.1",
            headerFields: ["Access-Control-Allow-Origin": "*"]
        )!
        task.didReceive(resp)
        task.didFinish()
        clearStopped(taskID)
    }

    private func serveData(
        _ data: Data,
        for task: any WKURLSchemeTask,
        taskID: ObjectIdentifier,
        requestURL: URL,
        ext: String,
        rangeHeader: String?
    ) {
        guard !isStopped(taskID) else {
            clearStopped(taskID)
            return
        }

        let mime = Self.mimeType(for: ext.lowercased())
        let total = data.count

        if let rangeHeader,
           let (start, end) = Self.parseByteRange(rangeHeader, totalLength: total) {
            let slice = data.subdata(in: start..<(end + 1))
            let headers: [String: String] = [
                "Content-Type": mime,
                "Content-Length": "\(slice.count)",
                "Content-Range": "bytes \(start)-\(end)/\(total)",
                "Accept-Ranges": "bytes",
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "public, max-age=31536000, immutable"
            ]
            let response = HTTPURLResponse(url: requestURL, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: headers)!
            guard !isStopped(taskID) else { clearStopped(taskID); return }
            task.didReceive(response)
            task.didReceive(slice)
            task.didFinish()
            clearStopped(taskID)
            return
        }

        let headers: [String: String] = [
            "Content-Type": mime,
            "Content-Length": "\(total)",
            "Accept-Ranges": "bytes",
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "public, max-age=31536000, immutable"
        ]
        let response = HTTPURLResponse(url: requestURL, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        guard !isStopped(taskID) else { clearStopped(taskID); return }
        task.didReceive(response)
        // Stream large payloads in 2 MB chunks to keep memory pressure minimal while staying ultra-fast
        let chunkSize = 2 * 1024 * 1024
        if total <= chunkSize {
            task.didReceive(data)
        } else {
            var offset = 0
            while offset < total {
                if isStopped(taskID) {
                    clearStopped(taskID)
                    return
                }
                let end = min(offset + chunkSize, total)
                task.didReceive(data.subdata(in: offset..<end))
                offset = end
            }
        }
        if !isStopped(taskID) {
            task.didFinish()
        }
        clearStopped(taskID)
    }

    private static func parseByteRange(_ header: String, totalLength: Int) -> (Int, Int)? {
        guard totalLength > 0, header.hasPrefix("bytes=") else { return nil }
        let spec = header.dropFirst("bytes=".count).split(separator: ",").first ?? ""
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let startStr = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let endStr = String(parts[1]).trimmingCharacters(in: .whitespaces)

        if startStr.isEmpty, let suffix = Int(endStr), suffix > 0 {
            let start = max(0, totalLength - suffix)
            return (start, totalLength - 1)
        }
        guard let start = Int(startStr), start >= 0, start < totalLength else { return nil }
        let end = endStr.isEmpty ? (totalLength - 1) : min(totalLength - 1, Int(endStr) ?? (totalLength - 1))
        guard end >= start else { return nil }
        return (start, end)
    }

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
        case "task", "glb", "bin": return "model/gltf-binary"
        default: return "application/octet-stream"
        }
    }
}

@MainActor
final class NextVRViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, PHPickerViewControllerDelegate {
    private var cameraContainerView: UIView!
    private var arSceneView: ARSCNView!
    private var fallbackPreviewLayer: AVCaptureVideoPreviewLayer?
    private var mrDimOverlayView: UIView!
    private var webView: WKWebView!

    private let motionManager = CMMotionManager()
    private let spatialPipeline = SpatialTrackingPipeline()
    private var batteryTimer: Timer?
    nonisolated(unsafe) private var foregroundObserver: NSObjectProtocol?

    private var isPassthroughVisible = false
    private var isHandsRequested = true
    private var isSixDofEnabled = true
    private var isWideCameraEnabled = false
    private var isMrDimEnabled = false

    private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 5.0 / 255.0, green: 7.0 / 255.0, blue: 12.0 / 255.0, alpha: 1.0)
        hapticGenerator.prepare()

        setupCameraBackgroundViews()
        setupWebView()
        setupSpatialPipelineCallbacks()
        startNativeGyroBridge()
        startBatteryBridge()
        observeAppLifecycle()
        loadNextVR()

        // Proactively request Camera permission right on launch so ARKit 6DoF, Hand Tracking & Passthrough never fail silently
        requestEssentialPermissionsOnLaunch()
    }

    deinit {
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        arSceneView.frame = cameraContainerView.bounds
        fallbackPreviewLayer?.frame = cameraContainerView.bounds
        mrDimOverlayView.frame = cameraContainerView.bounds
        updatePreviewOrientation()
    }

    private func setupCameraBackgroundViews() {
        cameraContainerView = UIView(frame: view.bounds)
        cameraContainerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cameraContainerView.backgroundColor = .black
        cameraContainerView.isHidden = true
        view.addSubview(cameraContainerView)

        // ARSCNView renders live 60fps camera feed when ARWorldTrackingConfiguration (6DoF) is active
        arSceneView = ARSCNView(frame: view.bounds)
        arSceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arSceneView.session = spatialPipeline.arSession
        arSceneView.automaticallyUpdatesLighting = false
        arSceneView.rendersCameraGrain = false
        arSceneView.rendersMotionBlur = false
        arSceneView.backgroundColor = .black
        cameraContainerView.addSubview(arSceneView)

        // Fallback AVCaptureVideoPreviewLayer when Ultra-Wide (0.5x) or 3DoF-only camera mode is used
        let layer = AVCaptureVideoPreviewLayer(session: spatialPipeline.captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = cameraContainerView.bounds
        layer.isHidden = true
        cameraContainerView.layer.addSublayer(layer)
        fallbackPreviewLayer = layer

        // Mixed-Reality Dimmer layer (`mrDim`)
        mrDimOverlayView = UIView(frame: view.bounds)
        mrDimOverlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mrDimOverlayView.backgroundColor = UIColor.black.withAlphaComponent(0.66)
        mrDimOverlayView.isUserInteractionEnabled = false
        mrDimOverlayView.isHidden = true
        cameraContainerView.addSubview(mrDimOverlayView)
    }

    private func updatePreviewOrientation() {
        let sceneOrientation = view.window?.windowScene?.interfaceOrientation ?? .landscapeRight
        if let connection = fallbackPreviewLayer?.connection {
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
        }
        spatialPipeline.updateInterfaceOrientation(sceneOrientation)
    }

    private func setupWebView() {
        let contentController = WKUserContentController()
        contentController.add(WeakScriptMessageHandler(delegate: self), name: "nextvrNative")

        // Auto-grant Web Orientation/Motion & Permissions API queries inside custom scheme nextvr://
        let polyfillJS = """
        (function() {
          if (typeof DeviceOrientationEvent !== 'undefined') {
            DeviceOrientationEvent.requestPermission = async function() { return 'granted'; };
          }
          if (typeof DeviceMotionEvent !== 'undefined') {
            DeviceMotionEvent.requestPermission = async function() { return 'granted'; };
          }
          if (navigator.permissions && navigator.permissions.query) {
            const origQuery = navigator.permissions.query.bind(navigator.permissions);
            navigator.permissions.query = async function(desc) {
              if (desc && (desc.name === 'camera' || desc.name === 'microphone' || desc.name === 'gyroscope' || desc.name === 'accelerometer' || desc.name === 'magnetometer')) {
                return { state: 'granted', onchange: null, addEventListener: function(){}, removeEventListener: function(){} };
              }
              return origQuery(desc);
            };
          }
        })();
        """
        let userScript = WKUserScript(source: polyfillJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(userScript)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        if let webRootURL = Bundle.main.url(forResource: "NexusVRWeb", withExtension: nil) ?? Bundle.main.url(forResource: "NextVRWeb", withExtension: nil) {
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
        guard (Bundle.main.url(forResource: "NexusVRWeb", withExtension: nil) ?? Bundle.main.url(forResource: "NextVRWeb", withExtension: nil)) != nil,
              let url = URL(string: "nextvr://app.local/index.html") else {
            return
        }
        webView.load(URLRequest(url: url))
    }

    // MARK: - Permissions Management

    private func observeAppLifecycle() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pushPermissionStatusToJS()
                self.updateSpatialTrackingState()
            }
        }
    }

    private func requestEssentialPermissionsOnLaunch() {
        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if camStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pushPermissionStatusToJS()
                    self.updateSpatialTrackingState()
                }
            }
        } else {
            pushPermissionStatusToJS()
            updateSpatialTrackingState()
        }
    }

    private func pushPermissionStatusToJS() {
        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let camStr: String
        switch camStatus {
        case .authorized: camStr = "authorized"
        case .notDetermined: camStr = "prompt"
        case .denied: camStr = "denied"
        case .restricted: camStr = "restricted"
        @unknown default: camStr = "unknown"
        }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let micStr: String
        switch micStatus {
        case .authorized: micStr = "authorized"
        case .notDetermined: micStr = "prompt"
        case .denied: micStr = "denied"
        case .restricted: micStr = "restricted"
        @unknown default: micStr = "unknown"
        }

        let arSupported = ARWorldTrackingConfiguration.isSupported
        let js = "window.__iosPermissionStatus && window.__iosPermissionStatus({ camera: '\(camStr)', microphone: '\(micStr)', arkit6DoF: \(arSupported ? "true" : "false") });"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - CoreMotion Gyroscope + DeviceMotion -> DOM

    private func startNativeGyroBridge() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let q = motion.attitude.quaternion
            let (alpha, beta, gamma) = Self.quaternionToW3CEulerDegrees(x: q.x, y: q.y, z: q.z, w: q.w)
            let orientAngle = self.currentWindowOrientationAngle()
            let ua = motion.userAcceleration
            let gr = motion.gravity
            // CoreMotion acceleration is in G-units; W3C devicemotion expects m/s^2
            let ax = (ua.x + gr.x) * 9.80665
            let ay = (ua.y + gr.y) * 9.80665
            let az = (ua.z + gr.z) * 9.80665

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
                  if (window.Walk && typeof window.Walk.onMotion === 'function') {
                    window.Walk.onMotion({ timeStamp: performance.now(), accelerationIncludingGravity: { x: %.3f, y: %.3f, z: %.3f } });
                  }
                })();
                """,
                orientAngle, alpha, beta, gamma, alpha, beta, gamma, ax, ay, az
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

    // MARK: - Spatial Tracking (ARKit 6DoF + Apple Vision Hand Tracking + AVCapture Fallback)

    private func setupSpatialPipelineCallbacks() {
        spatialPipeline.onHandsJSON = { [weak self] jsonString in
            Task { @MainActor [weak self] in
                guard let self, self.isHandsRequested else { return }
                self.webView?.evaluateJavaScript("window.__iosReceiveNativeHands && window.__iosReceiveNativeHands(\(jsonString));", completionHandler: nil)
            }
        }

        spatialPipeline.onSixDofPose = { [weak self] x, y, z, active in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let js = String(
                    format: "window.__iosReceiveSixDof && window.__iosReceiveSixDof(%.5f, %.5f, %.5f, %@);",
                    x, y, z, active ? "true" : "false"
                )
                self.webView?.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }

    private func updateSpatialTrackingState() {
        cameraContainerView.isHidden = !isPassthroughVisible
        mrDimOverlayView.isHidden = !(isPassthroughVisible && isMrDimEnabled)

        let shouldRunCamera = isPassthroughVisible || isHandsRequested || isSixDofEnabled
        let canUseARKit = ARWorldTrackingConfiguration.isSupported && isSixDofEnabled && !isWideCameraEnabled

        arSceneView.isHidden = !canUseARKit
        fallbackPreviewLayer?.isHidden = canUseARKit

        updatePreviewOrientation()
        spatialPipeline.configureMode(
            shouldRun: shouldRunCamera,
            useARKitSixDof: canUseARKit,
            detectHands: isHandsRequested,
            preferUltraWide: isWideCameraEnabled
        )

        if !canUseARKit {
            webView?.evaluateJavaScript("window.__iosReceiveSixDof && window.__iosReceiveSixDof(0, 0, 0, false);", completionHandler: nil)
        }
    }

    // MARK: - Native Photo Picker (Profile Avatar)

    private func presentNativePhotoPicker() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        let pickerBox = UncheckedSendableBox(value: picker)
        Task { @MainActor in
            pickerBox.value.dismiss(animated: true)
        }
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else { return }

        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage,
                  let dataURL = Self.squareAvatarDataURL(from: image, size: 160) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let escaped = dataURL.replacingOccurrences(of: "'", with: "")
                self.webView?.evaluateJavaScript(
                    "window.__iosReceivePickedPhotos && window.__iosReceivePickedPhotos(['\(escaped)']);",
                    completionHandler: nil
                )
            }
        }
    }

    nonisolated private static func squareAvatarDataURL(from image: UIImage, size: CGFloat) -> String? {
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: rendererFormat)
        let square = renderer.image { _ in
            let w = image.size.width
            let h = image.size.height
            let scale = max(size / max(w, 1), size / max(h, 1))
            let dw = w * scale
            let dh = h * scale
            let rect = CGRect(x: (size - dw) * 0.5, y: (size - dh) * 0.5, width: dw, height: dh)
            image.draw(in: rect)
        }
        guard let jpeg = square.jpegData(compressionQuality: 0.85) else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
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
        let sixdof = body["sixdof"] as? Bool
        let wideCamera = body["wideCamera"] as? Bool
        let mrDim = body["mrDim"] as? Bool
        let percent = body["percent"] as? Double

        Task { @MainActor [weak self] in
            guard let self else { return }
            switch action {
            case "ready":
                self.sendBatteryStatus()
                self.pushPermissionStatusToJS()
                self.updateSpatialTrackingState()
            case "startHands":
                self.isHandsRequested = true
                self.requestEssentialPermissionsOnLaunch()
                self.updateSpatialTrackingState()
            case "stopHands":
                self.isHandsRequested = false
                self.updateSpatialTrackingState()
            case "setEnvironment", "syncState":
                if let passthrough { self.isPassthroughVisible = passthrough }
                if let handsActive { self.isHandsRequested = handsActive }
                if let sixdof { self.isSixDofEnabled = sixdof }
                if let wideCamera { self.isWideCameraEnabled = wideCamera }
                if let mrDim { self.isMrDimEnabled = mrDim }
                self.updateSpatialTrackingState()
            case "resetSixDof":
                self.spatialPipeline.resetSixDofOrigin()
            case "setBrightness":
                if let percent {
                    let clamped = max(0.08, min(1.0, CGFloat(percent / 100.0)))
                    UIScreen.main.brightness = clamped
                }
            case "setVolume":
                break
            case "pickProfilePhoto":
                self.presentNativePhotoPicker()
            case "openAppSettings":
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
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
        pushPermissionStatusToJS()
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

    @available(iOS 15.0, *)
    func webView(
        _ webView: WKWebView,
        requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
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
            if url.scheme == "http" || url.scheme == "https" {
                webView.evaluateJavaScript(
                    "if (typeof window.nextvrMessage === 'function') { window.nextvrMessage('Abrindo link...'); }",
                    completionHandler: nil
                )
                UIApplication.shared.open(url)
            }
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

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = UIAlertController(title: "Next VR", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in
            completionHandler(false)
        })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(true)
        })
        present(alert, animated: true)
    }
}

// MARK: - Unified ARKit 6DoF + Apple Vision Hand Pose + AVCapture Fallback Pipeline

final class SpatialTrackingPipeline: NSObject, ARSessionDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let arSession = ARSession()
    let captureSession = AVCaptureSession()

    var onHandsJSON: (@Sendable (String) -> Void)?
    var onSixDofPose: (@Sendable (Double, Double, Double, Bool) -> Void)?

    private let controlQueue = DispatchQueue(label: "com.miguelwelli.nextvr.spatial-control", qos: .userInitiated)
    private let visionQueue = DispatchQueue(label: "com.miguelwelli.nextvr.vision", qos: .userInteractive)

    private let handRequest: VNDetectHumanHandPoseRequest = {
        let req = VNDetectHumanHandPoseRequest()
        req.maximumHandCount = 2
        return req
    }()

    private enum ActiveBackend {
        case none
        case arkit
        case avCapture(ultraWide: Bool)
    }

    private var activeBackend: ActiveBackend = .none
    private var detectHands = true
    private var isProcessingVision = false
    private var lastVisionTimestamp: CFTimeInterval = 0
    private var lastPoseTimestamp: CFTimeInterval = 0
    private var currentExifOrientation: CGImagePropertyOrientation = .up

    // ARKit 6DoF origin anchor for instant recentering (`Oi()` / `Xt.reset()`)
    private let originLock = NSLock()
    private var originPosition: SIMD3<Float>?
    private var originYawRadians: Float = 0
    private var needsOriginReset = true

    override init() {
        super.init()
        arSession.delegate = self
    }

    private static let jointOrder: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip
    ]

    func resetSixDofOrigin() {
        originLock.lock()
        needsOriginReset = true
        originLock.unlock()
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

    func configureMode(shouldRun: Bool, useARKitSixDof: Bool, detectHands: Bool, preferUltraWide: Bool) {
        visionQueue.async {
            self.detectHands = detectHands
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status == .authorized else {
            if status == .notDetermined && shouldRun {
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    if granted {
                        self?.configureMode(
                            shouldRun: shouldRun,
                            useARKitSixDof: useARKitSixDof,
                            detectHands: detectHands,
                            preferUltraWide: preferUltraWide
                        )
                    }
                }
            }
            return
        }

        controlQueue.async {
            if !shouldRun {
                self.stopAllInternal()
                return
            }

            if useARKitSixDof && ARWorldTrackingConfiguration.isSupported {
                if case .arkit = self.activeBackend {
                    return
                }
                if self.captureSession.isRunning {
                    self.captureSession.stopRunning()
                }
                let config = ARWorldTrackingConfiguration()
                config.worldAlignment = .gravity
                config.planeDetection = []
                config.isLightEstimationEnabled = false
                if let hiRes = ARWorldTrackingConfiguration.supportedVideoFormats.first(where: {
                    $0.framesPerSecond >= 60 && $0.imageResolution.width <= 1920
                }) {
                    config.videoFormat = hiRes
                }
                self.resetSixDofOrigin()
                self.arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
                self.activeBackend = .arkit
            } else {
                if case .arkit = self.activeBackend {
                    self.arSession.pause()
                    self.onSixDofPose?(0, 0, 0, false)
                }
                if case .avCapture(let currentUW) = self.activeBackend, currentUW == preferUltraWide, self.captureSession.isRunning {
                    return
                }
                self.reconfigureAVCaptureSession(preferUltraWide: preferUltraWide)
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                }
                self.activeBackend = .avCapture(ultraWide: preferUltraWide)
            }
        }
    }

    private func stopAllInternal() {
        switch activeBackend {
        case .arkit:
            arSession.pause()
            onSixDofPose?(0, 0, 0, false)
        case .avCapture:
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        case .none:
            break
        }
        activeBackend = .none
    }

    private func reconfigureAVCaptureSession(preferUltraWide: Bool) {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        captureSession.beginConfiguration()
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }
        captureSession.sessionPreset = .vga640x480

        let deviceTypes: [AVCaptureDevice.DeviceType] = preferUltraWide
            ? [.builtInUltraWideCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera, .builtInUltraWideCamera]

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .back
        )
        guard let camera = discovery.devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.setSampleBufferDelegate(self, queue: visionQueue)
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
        }

        captureSession.commitConfiguration()
    }

    // MARK: - ARSessionDelegate (Real Hardware VIO 6DoF + Hand Pose on same frame)

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = CACurrentMediaTime()

        // 1. Emit real 6DoF camera translation at ~60 Hz
        if now - lastPoseTimestamp >= 0.014 {
            lastPoseTimestamp = now
            let t = frame.camera.transform
            let worldPos = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)

            // Forward vector projected on horizontal XZ plane for yaw alignment on recenter
            let forwardX = -t.columns.2.x
            let forwardZ = -t.columns.2.z

            originLock.lock()
            if needsOriginReset || originPosition == nil {
                originPosition = worldPos
                // Align ARKit world horizontal axes with initial forward direction
                originYawRadians = atan2(forwardX, -forwardZ)
                needsOriginReset = false
            }
            let base = originPosition ?? worldPos
            let yaw0 = originYawRadians
            originLock.unlock()

            let dx = worldPos.x - base.x
            let dy = worldPos.y - base.y
            let dz = worldPos.z - base.z

            // Rotate horizontal displacement by -yaw0 so walking straight forward at start maps cleanly to -Z in Three.js
            let cosY = cos(-yaw0)
            let sinY = sin(-yaw0)
            let rx = Double(dx * cosY - dz * sinY)
            let rz = Double(dx * sinY + dz * cosY)
            let ry = Double(dy)

            let trackingOK: Bool
            switch frame.camera.trackingState {
            case .normal, .limited:
                trackingOK = true
            case .notAvailable:
                trackingOK = false
            }

            if trackingOK {
                onSixDofPose?(rx, ry, rz, true)
            }
        }

        // 2. Run Apple Vision 21-joint hand pose detection at ~30 Hz without retaining ARFrame
        guard detectHands, !isProcessingVision, now - lastVisionTimestamp >= 0.031 else { return }
        lastVisionTimestamp = now
        isProcessingVision = true

        let pixelBufferBox = UncheckedSendableBox(value: frame.capturedImage)
        visionQueue.async { [weak self] in
            guard let self else { return }
            defer { self.isProcessingVision = false }
            self.processPixelBufferForHands(pixelBufferBox.value, timestampSeconds: now)
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate (Fallback when 3DoF / Ultra-Wide 0.5x)

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard detectHands, !isProcessingVision else { return }
        let now = CACurrentMediaTime()
        if now - lastVisionTimestamp < 0.031 { return }
        lastVisionTimestamp = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isProcessingVision = true
        defer { isProcessingVision = false }

        processPixelBufferForHands(pixelBuffer, timestampSeconds: now)
    }

    private func processPixelBufferForHands(_ pixelBuffer: CVPixelBuffer, timestampSeconds: CFTimeInterval) {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: currentExifOrientation, options: [:])
        do {
            try handler.perform([handRequest])
            let observations = handRequest.results ?? []
            let json = buildHandsPayloadJSON(from: observations, timestampMs: timestampSeconds * 1000.0)
            onHandsJSON?(json)
        } catch {
            // Skip frame safely
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

private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
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
