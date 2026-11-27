import ActivityKit
import Foundation

struct DownloadAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var progress: Double   // 0...1
        var detail: String
    }
    var title: String
}
