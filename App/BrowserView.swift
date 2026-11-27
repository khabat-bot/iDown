import Combine
import SwiftUI
import WebKit

final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    @Published var address = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false

    /// Called with a ready-to-run request (cookies, referer, user agent included).
    var onDownload: ((URLRequest) -> Void)?

    private var lastActionMethod = "GET"
    private var bag = Set<AnyCancellable>()

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true

        webView.publisher(for: \.url)
            .sink { [weak self] url in if let url { self?.address = url.absoluteString } }
            .store(in: &bag)
        webView.publisher(for: \.canGoBack)
            .sink { [weak self] in self?.canGoBack = $0 }
            .store(in: &bag)
        webView.publisher(for: \.canGoForward)
            .sink { [weak self] in self?.canGoForward = $0 }
            .store(in: &bag)
        webView.publisher(for: \.isLoading)
            .sink { [weak self] in self?.isLoading = $0 }
            .store(in: &bag)
    }

    func load(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var target: URL?
        if let url = URL(string: text), let scheme = url.scheme, scheme.hasPrefix("http") {
            target = url
        } else if !text.contains(" "), text.contains("."), let url = URL(string: "https://" + text) {
            target = url
        } else {
            var comps = URLComponents(string: "https://www.google.com/search")!
            comps.queryItems = [URLQueryItem(name: "q", value: text)]
            target = comps.url
        }
        if let target { webView.load(URLRequest(url: target)) }
    }

    // MARK: Catching downloads

    private func startDownload(url: URL) {
        let referer = webView.url?.absoluteString
        webView.evaluateJavaScript("navigator.userAgent") { [weak self] result, _ in
            guard let self else { return }
            let userAgent = result as? String
            self.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let host = url.host ?? ""
                let path = url.path.isEmpty ? "/" : url.path
                let matching = cookies.filter { cookie in
                    let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                    return (host == domain || host.hasSuffix("." + domain))
                        && path.hasPrefix(cookie.path)
                        && (!cookie.isSecure || url.scheme == "https")
                }
                var request = URLRequest(url: url)
                request.httpShouldHandleCookies = false
                request.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: matching)
                if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
                if let referer { request.setValue(referer, forHTTPHeaderField: "Referer") }
                DispatchQueue.main.async { self.onDownload?(request) }
            }
        }
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        lastActionMethod = navigationAction.request.httpMethod ?? "GET"
        // Links with the HTML "download" attribute.
        if navigationAction.shouldPerformDownload,
           lastActionMethod == "GET",
           let url = navigationAction.request.url {
            decisionHandler(.cancel)
            startDownload(url: url)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let http = navigationResponse.response as? HTTPURLResponse
        let disposition = http?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        let isFile = disposition.contains("attachment") || !navigationResponse.canShowMIMEType
        if isFile, lastActionMethod == "GET", let url = navigationResponse.response.url {
            decisionHandler(.cancel)
            startDownload(url: url)
        } else {
            decisionHandler(.allow)
        }
    }

    // Open target="_blank" links in the same view so download buttons keep working.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct BrowserView: View {
    @ObservedObject var model: BrowserModel
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Search or enter address", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.webSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit {
                        model.load(text)
                        focused = false
                    }
                if model.isLoading { ProgressView() }
            }
            .padding(8)

            WebViewContainer(webView: model.webView)

            HStack {
                Button { model.webView.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!model.canGoBack)
                Spacer()
                Button { model.webView.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!model.canGoForward)
                Spacer()
                Button { model.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
            }
            .font(.title3)
            .padding(.horizontal, 32)
            .padding(.vertical, 10)
        }
        .onReceive(model.$address) { newAddress in
            if !focused { text = newAddress }
        }
    }
}
