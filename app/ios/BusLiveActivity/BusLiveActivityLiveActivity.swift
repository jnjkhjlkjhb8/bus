import ActivityKit
import SwiftUI
import WidgetKit

struct BusLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BusLiveActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "tram.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.routeOrTrain)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text("下一站 \(context.state.nextStation)")
                        .font(.system(size: 16, weight: .semibold))
                    HStack(spacing: 8) {
                        Text(context.attributes.fromStation)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        ProgressView(value: context.state.progressPercent)
                            .tint(.primary)
                        Text(context.state.nextStation)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image(systemName: "tram.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.attributes.routeOrTrain)
                                .font(.system(size: 15))
                                .foregroundColor(Color(.systemGray))
                            Text("下一站 \(context.state.nextStation)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 0) {
                        HStack(spacing: 9) {
                            Text(context.attributes.fromStation)
                                .font(.system(size: 12))
                                .foregroundColor(Color(.systemGray))
                            ProgressView(value: context.state.progressPercent)
                                .tint(Color(white: 0.8))
                                .background(Color(white: 0.25))
                                .clipShape(Capsule())
                            Text(context.state.nextStation)
                                .font(.system(size: 12))
                                .foregroundColor(Color(.systemGray))
                        }
                        .padding(.horizontal, 16)
                        Button("開啟詳細資訊") {}
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                            .foregroundColor(.white)
                            .font(.system(size: 18, weight: .medium))
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                    }
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: "tram.circle.fill")
                        .foregroundColor(.white)
                    Text("下一站 \(context.state.nextStation)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            } compactTrailing: {
                _CircularProgress(value: context.state.progressPercent)
            } minimal: {
                _CircularProgress(value: context.state.progressPercent)
            }
        }
    }
}

private struct _CircularProgress: View {
    let value: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: value)
                .stroke(Color(red: 1, green: 0.22, blue: 0.24), lineWidth: 3)
                .rotationEffect(.degrees(-90))
            Text("\(Int(value * 100))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(red: 1, green: 0.22, blue: 0.24))
        }
        .frame(width: 28, height: 28)
    }
}
