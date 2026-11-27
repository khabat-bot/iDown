import ActivityKit
import SwiftUI
import WidgetKit

@main
struct DownloadWidgetBundle: WidgetBundle {
    var body: some Widget {
        DownloadLiveActivity()
    }
}

struct DownloadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                    Text(context.attributes.title).font(.headline)
                    Spacer()
                    Text("\(Int(context.state.progress * 100))%").monospacedDigit()
                }
                ProgressView(value: context.state.progress)
                Text(context.state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "arrow.down.circle.fill")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.progress * 100))%").monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading) {
                        ProgressView(value: context.state.progress)
                        Text(context.state.detail).font(.caption)
                    }
                }
            } compactLeading: {
                Image(systemName: "arrow.down.circle.fill")
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))%").monospacedDigit()
            } minimal: {
                Image(systemName: "arrow.down.circle.fill")
            }
        }
    }
}
