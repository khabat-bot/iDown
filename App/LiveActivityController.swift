import ActivityKit
import Foundation

final class LiveActivityController {
    static let shared = LiveActivityController()

    private var activity: Activity<DownloadAttributes>?
    private var lastUpdate = Date.distantPast

    func start() {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = DownloadAttributes.ContentState(progress: 0, detail: "Starting…")
        activity = try? Activity.request(
            attributes: DownloadAttributes(title: "Downloading"),
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
    }

    func update(progress: Double, detail: String) {
        guard let activity, Date().timeIntervalSince(lastUpdate) > 1 else { return }
        lastUpdate = Date()
        let state = DownloadAttributes.ContentState(progress: progress, detail: detail)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end(detail: String) {
        guard let activity else { return }
        self.activity = nil
        let state = DownloadAttributes.ContentState(progress: 1, detail: detail)
        Task {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(30))
            )
        }
    }
}
