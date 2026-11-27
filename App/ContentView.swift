import SwiftUI

struct ContentView: View {
    @StateObject private var browser = BrowserModel()
    @State private var showToast = false

    var body: some View {
        TabView {
            DownloadsView()
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
            BrowserView(model: browser)
                .tabItem { Label("Browser", systemImage: "globe") }
        }
        .overlay(alignment: .top) {
            if showToast {
                Text("Download started")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: showToast)
        .onAppear {
            browser.onDownload = { request in
                DownloadManager.shared.download(request)
                showToast = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showToast = false }
            }
        }
    }
}
