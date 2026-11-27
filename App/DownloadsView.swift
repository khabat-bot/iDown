import SwiftUI

struct DownloadsView: View {
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
                Section("Downloads (saved in Files → On My iPhone → iDown)") {
                    ForEach(manager.items) { item in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).lineLimit(1)
                                switch item.state {
                                case .running:
                                    if item.total > 0 {
                                        ProgressView(value: item.progress)
                                    } else {
                                        ProgressView().progressViewStyle(.linear)
                                    }
                                    Text(item.statusLine)
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                case .finished:
                                    Text("Finished · \(formatBytes(item.written)) · tap to open in Files")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                case .failed(let message):
                                    Text(message).font(.caption).foregroundStyle(.red)
                                case .cancelled:
                                    Text("Cancelled").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if case .running = item.state {
                                Button {
                                    manager.cancel(item.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let url = item.fileURL { openInFiles(url) }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                manager.delete(item.id)
                            } label: {
                                Label(item.fileURL == nil ? "Remove" : "Delete file", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("iDown")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear finished") { manager.clearFinished() }
                        .disabled(!hasInactiveItems)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var hasInactiveItems: Bool {
        manager.items.contains { item in
            if case .running = item.state { return false }
            return true
        }
    }

    /// Opens the Files app at the downloaded file (the app's Documents folder is visible in Files).
    private func openInFiles(_ url: URL) {
        let link = url.absoluteString.replacingOccurrences(of: "file://", with: "shareddocuments://")
        if let filesURL = URL(string: link) {
            UIApplication.shared.open(filesURL)
        }
    }
}
