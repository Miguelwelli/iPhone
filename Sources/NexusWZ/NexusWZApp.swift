import AVFoundation
import SwiftUI
import UIKit
import WebKit

@main
struct NexusWZApp: App {
    init() {
        configureAudioSession()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    var body: some Scene {
        WindowGroup {
            GameRootView()
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

struct GameRootView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> GameViewController {
        GameViewController()
    }

    func updateUIViewController(_ uiViewController: GameViewController, context: Context) {}
}

@MainActor
final class GameViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!

    override var prefersStatusBarHidden: Bool {
        true
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        true
    }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        .all
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .allButUpsideDown
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 9.0 / 255.0, green: 13.0 / 255.0, blue: 22.0 / 255.0, alpha: 1.0)
        setupWebView()
        loadLocalGame()
    }

    private func setupWebView() {
        let contentController = WKUserContentController()
        contentController.add(WeakScriptMessageHandler(delegate: self), name: "nexusBridge")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 9.0 / 255.0, green: 13.0 / 255.0, blue: 22.0 / 255.0, alpha: 1.0)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = self
        webView.uiDelegate = self

        view.addSubview(webView)
    }

    private func loadLocalGame() {
        guard let webRootURL = Bundle.main.url(forResource: "WebGame", withExtension: nil) else {
            showFallbackMessage("Arquivos do jogo não encontrados no pacote (WebGame).")
            return
        }
        let indexURL = webRootURL.appendingPathComponent("index.html")
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            showFallbackMessage("index.html não encontrado em WebGame.")
            return
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: webRootURL)
    }

    private func showFallbackMessage(_ text: String) {
        let html = """
        <!DOCTYPE html>
        <html>
        <body style="margin:0;display:grid;place-items:center;height:100vh;background:#090d16;color:#fbbf24;font-family:system-ui,sans-serif;text-align:center;padding:24px;">
          <div>
            <h2>NEXUS WZ</h2>
            <p style="color:#cbd5e1;">\(text)</p>
          </div>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - WKScriptMessageHandler

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "nexusBridge" else { return }
        let rawBody = message.body
        guard let dict = rawBody as? [String: Any],
              let action = dict["action"] as? String else { return }

        let textValue = dict["text"] as? String
        let fileName = dict["name"] as? String
        let base64Value = dict["base64"] as? String

        Task { @MainActor [weak self] in
            guard let self else { return }
            switch action {
            case "copy":
                if let textValue {
                    UIPasteboard.general.string = textValue
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            case "exportFile":
                if let fileName, let base64Value,
                   let data = Data(base64Encoded: base64Value) {
                    self.shareExportedFile(name: fileName, data: data)
                }
            default:
                break
            }
        }
    }

    private func shareExportedFile(name: String, data: Data) {
        let safeName = URL(fileURLWithPath: name).lastPathComponent
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
        do {
            try data.write(to: tempURL, options: .atomic)
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
                popover.permittedArrowDirections = []
            }
            present(activityVC, animated: true)
        } catch {
            // Ignora falha temporária de escrita
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let isStudio = webView.url?.lastPathComponent == "customizador.html"
        webView.scrollView.isScrollEnabled = isStudio
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if url.isFileURL || url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" {
            decisionHandler(.allow)
            return
        }
        if (url.scheme == "http" || url.scheme == "https") && navigationAction.navigationType == .linkActivated {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: - WKUIDelegate

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = UIAlertController(title: "NEXUS WZ", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler()
        })
        present(alert, animated: true)
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
