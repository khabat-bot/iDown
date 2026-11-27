import Combine
import SwiftUI
import WebKit

final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    let webView: WKWebView
    @Published var address = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false

    /// Called when the web view starts saving a file.
    var onDownloadStarted: (() -> Void)?

    private struct ActiveDownload {
        let id: Int
        let destination: URL
        let observer: AnyCancellable
    }

    private var active: [ObjectIdentifier: ActiveDownload] = [:]
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

    // MARK: Deciding what is a download

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Links with the HTML "download" attribute (including blob: links made by scripts).
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let http = navigationResponse.response as? HTTPURLResponse
        let disposition = http?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        let isFile = disposition.contains("attachment") || !navigationResponse.canShowMIMEType
        decisionHandler(isFile ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
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

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let manager = DownloadManager.shared
        let name = suggestedFilename.isEmpty ? "download" : suggestedFilename
        let destination = manager.uniqueDestination(named: name)
        let id = manager.beginExternal(name: destination.lastPathComponent) { [weak download] in
            download?.cancel { _ in }
        }

        let progress = download.progress
        let observer = progress.publisher(for: \.completedUnitCount)
            .receive(on: DispatchQueue.main)
            .sink { completed in
                let total = max(progress.totalUnitCount, 0)
                manager.updateExternal(id, written: completed, total: total)
            }
        active[ObjectIdentifier(download)] = ActiveDownload(id: id, destination: destination, observer: observer)
        onDownloadStarted?()
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let entry = active.removeValue(forKey: ObjectIdentifier(download)) else { return }
        entry.observer.cancel()
        DownloadManager.shared.finishExternal(entry.id, fileURL: entry.destination)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let manager = DownloadManager.shared
        let entry = active.removeValue(forKey: ObjectIdentifier(download))
        entry?.observer.cancel()
        if let destination = entry?.destination {
            try? FileManager.default.removeItem(at: destination) // drop the partial file
        }
        let id = entry?.id ?? manager.beginExternal(name: "download", cancel: {})
        manager.failExternal(id, message: error.localizedDescription)
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
