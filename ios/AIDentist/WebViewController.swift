import UIKit
import WebKit
import SafariServices

/// AI Dentist — оболочка над веб-панелью клиники (iPhone и iPad).
/// При запуске — экран выбора клиники (launcher/index.html из приложения), затем панель https://<клиника>.
/// PDF и файлы (/api/…) открываются в окне Safari внутри приложения, WhatsApp/Telegram/телефон — в своих приложениях.
/// Сменить клинику: кнопка на заставке при запуске или встряхнуть телефон.
final class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {

    private var web: WKWebView!
    private let userContent = WKUserContentController()
    private let brand = UIColor(red: 22 / 255, green: 105 / 255, blue: 90 / 255, alpha: 1)

    private var clinic: String {
        get { UserDefaults.standard.string(forKey: "clinic") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "clinic") }
    }
    private var clinicHost: String? { URL(string: clinic)?.host?.lowercased() }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = brand

        userContent.add(WeakScriptHandler(self), name: "aidentist")
        let cfg = WKWebViewConfiguration()
        cfg.userContentController = userContent
        cfg.websiteDataStore = .default()
        cfg.allowsInlineMediaPlayback = true
        cfg.applicationNameForUserAgent = "Mobile/15E148 AIDentistApp/\(appVersion) (iOS)"
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true

        web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.isOpaque = false
        web.backgroundColor = brand
        web.allowsBackForwardNavigationGestures = false
        web.allowsLinkPreview = false

        let refresh = UIRefreshControl()
        refresh.tintColor = .gray
        refresh.addTarget(self, action: #selector(pullToRefresh(_:)), for: .valueChanged)
        web.scrollView.refreshControl = refresh

        // Сверху — под строкой состояния (зелёная полоса), остальное — на весь экран.
        web.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(web)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        showLauncher(query: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    // MARK: - Экран выбора клиники

    private func installBridge() {
        userContent.removeAllUserScripts()
        let saved = (try? String(data: JSONEncoder().encode(clinic), encoding: .utf8)) ?? "\"\""
        let js = """
        window.AIDentistNative = {
          clinic: \(saved),
          setClinic: function (u) { window.webkit.messageHandlers.aidentist.postMessage({ action: "setClinic", url: String(u) }); }
        };
        """
        userContent.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    private func showLauncher(query: String?) {
        installBridge()
        guard let page = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "launcher") else { return }
        var target = page
        if let q = query, var c = URLComponents(url: page, resolvingAgainstBaseURL: false) {
            c.query = q
            target = c.url ?? page
        }
        web.loadFileURL(target, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard web.url?.isFileURL == true,                       // менять клинику может только наш экран
              let body = message.body as? [String: Any],
              body["action"] as? String == "setClinic",
              let raw = body["url"] as? String,
              let u = URL(string: raw.trimmingCharacters(in: .whitespaces)),
              u.scheme == "https", let host = u.host, !host.isEmpty else { return }
        var c = URLComponents()
        c.scheme = "https"
        c.host = host
        c.port = u.port
        guard let origin = c.url?.absoluteString, let start = URL(string: origin + "/") else { return }
        clinic = origin
        installBridge()
        web.load(URLRequest(url: start))
    }

    // MARK: - Навигация

    private func isClinic(_ url: URL) -> Bool {
        guard let h = clinicHost else { return false }
        return url.scheme == "https" && url.host?.lowercased() == h
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if url.isFileURL || url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" {
            return decisionHandler(.allow)
        }
        let mainFrame = action.targetFrame?.isMainFrame ?? true
        if !mainFrame { return decisionHandler(.allow) }
        if isClinic(url) {
            if url.path.hasPrefix("/api/") { openInApp(url); return decisionHandler(.cancel) }  // PDF, файлы
            return decisionHandler(.allow)
        }
        openExternal(url)
        decisionHandler(.cancel)
    }

    // target=_blank и window.open
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url {
            if isClinic(url) { openInApp(url) } else { openExternal(url) }
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.scrollView.refreshControl?.endRefreshing()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadError(error)
    }

    private func handleLoadError(_ error: Error) {
        web.scrollView.refreshControl?.endRefreshing()
        let e = error as NSError
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
        if e.domain == "WebKitErrorDomain" && e.code == 102 { return }   // загрузка прервана нашим же решением
        if let failing = e.userInfo[NSURLErrorFailingURLErrorKey] as? URL, failing.isFileURL { return }
        showLauncher(query: "error=1")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView.url == nil { showLauncher(query: nil) } else { webView.reload() }
    }

    @objc private func pullToRefresh(_ sender: UIRefreshControl) {
        if web.url?.isFileURL == true { sender.endRefreshing(); return }
        web.reload()
    }

    private func openInApp(_ url: URL) {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = brand
        vc.dismissButtonStyle = .close
        present(vc, animated: true)
    }

    private func openExternal(_ url: URL) {
        UIApplication.shared.open(url, options: [:]) { ok in
            if !ok, url.scheme == "http" || url.scheme == "https" { self.openInApp(url) }
        }
    }

    // MARK: - Сменить клинику (встряхнуть)

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake, presentedViewController == nil, web.url?.isFileURL != true else { return }
        let a = UIAlertController(title: "AI Dentist", message: "Сменить клинику?", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        a.addAction(UIAlertAction(title: "Сменить", style: .default) { _ in self.showLauncher(query: "change=1") })
        present(a, animated: true)
    }

    // MARK: - alert / confirm / prompt из страницы

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        presentOrSkip(a) { completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        presentOrSkip(a) { completionHandler(false) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        a.addTextField { $0.text = defaultText }
        a.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in completionHandler(nil) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
        presentOrSkip(a) { completionHandler(nil) }
    }

    private func presentOrSkip(_ a: UIAlertController, otherwise: () -> Void) {
        if presentedViewController == nil { present(a, animated: true) } else { otherwise() }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

/// Чтобы WKUserContentController не держал контроллер навсегда.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}
