import Foundation

struct DownloadItem: Identifiable {
    enum State { case running, finished, failed(String) }
    let id: Int
    var name: String
    var written: Int64 = 0
    var total: Int64 = 0
    var fileURL: URL?
    var state: State = .running
    var speed: Double = 0            // bytes per second, smoothed
    var lastSampleTime: Date?
    var lastSampleBytes: Int64 = 0

    var progress: Double { total > 0 ? min(Double(written) / Double(total), 1) : 0 }

    /// e.g. "12.3 MB of 45.6 MB · 27% · 2.1 MB/s"
    var statusLine: String {
        var parts: [String] = []
        if total > 0 {
            parts.append("\(formatBytes(written)) of \(formatBytes(total))")
            parts.append("\(Int(progress * 100))%")
        } else {
            parts.append(formatBytes(written))
        }
        if speed > 0 { parts.append("\(formatBytes(Int64(speed)))/s") }
        return parts.joined(separator: " · ")
    }
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()

    var backgroundCompletionHandler: (() -> Void)?
    @Published private(set) var items: [DownloadItem] = []

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.khabat.idown.session")
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    private override init() {
        super.init()
        // Re-attach to downloads that kept running while the app was gone.
        session.getAllTasks { [weak self] tasks in
            DispatchQueue.main.async {
                guard let self else { return }
                for task in tasks where task.state == .running || task.state == .suspended {
                    self.items.append(DownloadItem(
                        id: task.taskIdentifier,
                        name: task.originalRequest?.url?.lastPathComponent ?? "file",
                        written: task.countOfBytesReceived,
                        total: task.countOfBytesExpectedToReceive
                    ))
                }
                if !self.items.isEmpty { self.beginKeepAlive() }
            }
        }
    }

    func download(_ url: URL) {
        download(URLRequest(url: url))
    }

    func download(_ request: URLRequest) {
        guard let url = request.url else { return }
        let task = session.downloadTask(with: request)
        let name = url.lastPathComponent.isEmpty ? (url.host ?? "file") : url.lastPathComponent
        items.insert(DownloadItem(id: task.taskIdentifier, name: name), at: 0)
        beginKeepAlive()
        task.resume()
    }

    // MARK: Downloads run by the web view (WKDownload)

    private var nextExternalID = -1

    func uniqueDestination(named name: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return uniqueURL(in: docs, name: name)
    }

    func beginExternal(name: String) -> Int {
        let id = nextExternalID
        nextExternalID -= 1
        items.insert(DownloadItem(id: id, name: name), at: 0)
        beginKeepAlive()
        return id
    }

    func updateExternal(_ id: Int, written: Int64, total: Int64) {
        recordProgress(id, written: written, total: total)
        refreshLiveActivity()
    }

    func finishExternal(_ id: Int, fileURL: URL) {
        let size = fileSize(fileURL)
        update(id) {
            $0.name = fileURL.lastPathComponent
            $0.fileURL = fileURL
            $0.written = size
            $0.total = size
            $0.speed = 0
            $0.state = .finished
        }
        finishIfIdle()
    }

    func failExternal(_ id: Int, message: String) {
        update(id) { $0.state = .failed(message) }
        finishIfIdle()
    }

    // MARK: Keep-alive helpers

    private func beginKeepAlive() {
        KeepAlive.shared.start()
        LiveActivityController.shared.start()
    }

    private func refreshLiveActivity() {
        let running = items.filter { if case .running = $0.state { return true } else { return false } }
        guard !running.isEmpty else { return }
        let written = running.reduce(0) { $0 + $1.written }
        let total = running.reduce(0) { $0 + $1.total }
        let progress = total > 0 ? Double(written) / Double(total) : 0
        let speed = running.reduce(0.0) { $0 + $1.speed }
        let label = running.count == 1 ? running[0].name : "\(running.count) files"
        var stats = total > 0 ? "\(formatBytes(written)) of \(formatBytes(total))" : formatBytes(written)
        if speed > 0 { stats += " · \(formatBytes(Int64(speed)))/s" }
        LiveActivityController.shared.update(progress: progress, detail: "\(label) · \(stats)")
    }

    private func finishIfIdle() {
        let anyRunning = items.contains { if case .running = $0.state { return true } else { return false } }
        guard !anyRunning else { return }
        KeepAlive.shared.stop()
        LiveActivityController.shared.end(detail: "Done")
    }

    /// Stores progress and refreshes the smoothed speed about once per second.
    private func recordProgress(_ id: Int, written: Int64, total: Int64) {
        update(id) { item in
            let now = Date()
            if let last = item.lastSampleTime {
                let elapsed = now.timeIntervalSince(last)
                if elapsed >= 1 {
                    let instant = Double(written - item.lastSampleBytes) / elapsed
                    item.speed = item.speed == 0 ? instant : item.speed * 0.6 + instant * 0.4
                    item.lastSampleTime = now
                    item.lastSampleBytes = written
                }
            } else {
                item.lastSampleTime = now
                item.lastSampleBytes = written
            }
            item.written = written
            item.total = total
        }
    }

    private func fileSize(_ url: URL) -> Int64 {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber
        return size?.int64Value ?? 0
    }

    private func update(_ id: Int, _ change: (inout DownloadItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        recordProgress(downloadTask.taskIdentifier, written: totalBytesWritten, total: totalBytesExpectedToWrite)
        refreshLiveActivity()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let id = downloadTask.taskIdentifier
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let suggested = downloadTask.response?.suggestedFilename
            ?? downloadTask.originalRequest?.url?.lastPathComponent
            ?? "download"
        let destination = uniqueURL(in: docs, name: suggested.isEmpty ? "download" : suggested)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            let size = fileSize(destination)
            update(id) {
                $0.name = destination.lastPathComponent
                $0.fileURL = destination
                $0.written = size
                $0.total = size
                $0.speed = 0
                $0.state = .finished
            }
        } catch {
            update(id) { $0.state = .failed(error.localizedDescription) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            update(task.taskIdentifier) { $0.state = .failed(error.localizedDescription) }
        }
        finishIfIdle()
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        backgroundCompletionHandler?()
        backgroundCompletionHandler = nil
    }

    private func uniqueURL(in dir: URL, name: String) -> URL {
        var candidate = dir.appendingPathComponent(name)
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            candidate = dir.appendingPathComponent(newName)
            n += 1
        }
        return candidate
    }
}
