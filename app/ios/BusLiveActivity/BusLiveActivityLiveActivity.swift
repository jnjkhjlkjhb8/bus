import ActivityKit
import SwiftUI
import WidgetKit

struct BusLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BusLiveActivityAttributes.self) { context in
            if context.state.mode == "waiting" {
                WaitingCard(context: context)
            } else {
                RidingCard(context: context)
            }
        } dynamicIsland: { context in
            let waiting = context.state.mode == "waiting"
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image(systemName: waiting ? "figure.wave" : "tram.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.attributes.routeOrTrain)
                                .font(.system(size: 15))
                                .foregroundColor(Color(.systemGray))
                            Text(waiting
                                 ? "於 \(context.attributes.fromStation) 上車"
                                 : "下一站 \(context.state.nextStation)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if waiting {
                        VStack(spacing: 0) {
                            if let eta = context.state.etaDate, eta > Date() {
                                Text(timerInterval: Date()...eta, countsDown: true)
                                    .font(.system(size: 22, weight: .semibold))
                                    .monospacedDigit()
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("進站中")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                            }
                            if context.state.walkMinutes > 0 {
                                Text("步行 \(context.state.walkMinutes) 分至上車站")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(.systemGray))
                                    .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    } else {
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
                            Text("\(context.state.alightStation ?? "") 下車・剩 \(context.state.remainingStops ?? 0) 站")
                                .font(.system(size: 12))
                                .foregroundColor(Color(.systemGray))
                                .padding(.top, 8)
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
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: waiting ? "figure.wave" : "tram.circle.fill")
                        .foregroundColor(.white)
                    Text(waiting
                         ? "下一班 \(context.attributes.routeOrTrain)"
                         : "下一站 \(context.state.nextStation)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            } compactTrailing: {
                if waiting {
                    if let eta = context.state.etaDate, eta > Date() {
                        Text(timerInterval: Date()...eta, countsDown: true)
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .frame(maxWidth: 44)
                    } else {
                        Text("進站中")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                } else {
                    _CircularProgress(value: context.state.progressPercent)
                }
            } minimal: {
                _CircularProgress(value: context.state.progressPercent)
            }
        }
    }
}

@available(iOS 16.1, *)
private struct RidingCard: View {
    let context: ActivityViewContext<BusLiveActivityAttributes>

    var body: some View {
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
    }
}

@available(iOS 16.1, *)
private struct WaitingCard: View {
    let context: ActivityViewContext<BusLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.wave")
                .font(.system(size: 40))
            VStack(alignment: .leading, spacing: 4) {
                Text("下一班 \(context.attributes.routeOrTrain)")
                    .font(.system(size: 16, weight: .semibold))
                Text("於 \(context.attributes.fromStation) 上車")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                if context.state.walkMinutes > 0 {
                    Text("步行 \(context.state.walkMinutes) 分至上車站")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if let eta = context.state.etaDate, eta > Date() {
                // Self-ticking: no channel update needed per second.
                Text(timerInterval: Date()...eta, countsDown: true)
                    .font(.system(size: 24, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 72)
            } else {
                Text("進站中")
                    .font(.system(size: 18, weight: .semibold))
            }
        }
        .padding(16)
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
