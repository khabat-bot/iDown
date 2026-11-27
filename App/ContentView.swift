import SwiftUI

struct ContentView: View {
    @ObservedObject private var manager = DownloadManager.shared
    @State private var urlText = ""

    var body: some View {
        NavigationView {
            List {
                Section {
                    TextField("https://example.com/file.zip", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Download") {
                        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let url = URL(string: trimmed),
                              let scheme = url.scheme, scheme.hasPrefix("http") else { return }
                        manager.download(url)
                        urlText = ""
                    }
                    Button("Paste from clipboard") {
                        urlText = UIPasteboard.general.string ?? ""
                    }
                }
                Section("Downloads (saved in Files → On My iPhone → BG Downloader)") {
                    ForEach(manager.items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).lineLimit(1)
                            switch item.state {
                            case .running:
                                ProgressView(value: item.progress)
                            case .finished:
                                Text("Finished").font(.caption).foregroundStyle(.green)
                            case .failed(let message):
                                Text(message).font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("BG Downloader")
        }
        .navigationViewStyle(.stack)
    }
}
