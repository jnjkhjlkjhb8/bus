import ActivityKit
import SwiftUI
import WidgetKit

/// SF Symbol for the transit type. All glyphs used here exist on iOS 16.
/// "train.side.front.car" is available from iOS 16, so no availability guard
/// is required; kept centralized so every region renders the same glyph.
private func typeGlyph(_ type: String) -> String {
    switch type {
    case "bus":
        return "bus.fill"
    case "mrt":
        return "tram.fill"
    case "tra", "thsr":
        return "train.side.front.car"
    default:
        return "tram.fill"
    }
}

/// Whole minutes until `eta`, clamped to at least 1 so the minimal view never
/// shows "0分" while a countdown is still pending.
private func minutesUntil(_ eta: Date) -> Int {
    max(1, Int(ceil(eta.timeIntervalSinceNow / 60)))
}

struct BusLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BusLiveActivityAttributes.self) { context in
            // Lock-screen / banner presentation.
            Group {
                if context.state.mode == "board" {
                    BoardCard(context: context)
                } else if isPinned(context.state) {
                    PinnedCard(context: context)
                } else if context.state.mode == "waiting" {
                    WaitingCard(context: context)
                } else {
                    RidingCard(context: context)
                }
            }
            // Keep the system default background for lock-screen cards.
            .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            let board = context.state.mode == "board"
            let waiting = context.state.mode == "waiting"
            let pinned = isPinned(context.state)
            let glyph = typeGlyph(context.attributes.type)
            let boardRows = context.state.routes ?? []
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if board {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("站牌")
                                .font(.system(size: 12))
                                .foregroundColor(Color(.systemGray))
                            Text(context.state.stopName ?? "")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        .padding(.leading, 4)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: glyph)
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pinned
                                     ? (context.state.routeNumber ?? context.attributes.routeOrTrain)
                                     : (waiting ? "下一班" : context.attributes.routeOrTrain))
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(.systemGray))
                                    .lineLimit(1)
                                Text(pinned
                                     ? (context.state.plate ?? "")
                                     : (waiting
                                        ? context.attributes.routeOrTrain
                                        : "下一站 \(context.state.nextStation)"))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.leading, 4)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if board {
                            // Board rows render in the bottom region; the
                            // trailing region stays empty (no single ETA to
                            // headline when the board lists several routes).
                            EmptyView()
                        } else if pinned {
                            if let eta = context.state.etaDate, eta > Date() {
                                Text(timerInterval: Date()...eta, countsDown: true)
                                    .font(.system(size: 26, weight: .semibold))
                                    .monospacedDigit()
                                    .multilineTextAlignment(.trailing)
                                    .foregroundColor(.white)
                                    .frame(width: 78)
                                Text("後進站")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(.systemGray))
                            } else {
                                Text("進站中")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        } else if waiting {
                            if let eta = context.state.etaDate, eta > Date() {
                                // Self-ticking timer: avoids a per-second push
                                // to refresh the countdown.
                                Text(timerInterval: Date()...eta, countsDown: true)
                                    .font(.system(size: 26, weight: .semibold))
                                    .monospacedDigit()
                                    .multilineTextAlignment(.trailing)
                                    .foregroundColor(.white)
                                    .frame(width: 78)
                                Text("後進站")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(.systemGray))
                            } else {
                                Text("進站中")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        } else {
                            Text("\(context.state.remainingStops ?? 0)站")
                                .font(.system(size: 26, weight: .semibold))
                                .monospacedDigit()
                                .foregroundColor(.white)
                            Text("\(context.state.alightStation ?? "") 下車")
                                .font(.system(size: 11))
                                .foregroundColor(Color(.systemGray))
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if board {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(boardRows.prefix(3).enumerated()), id: \.offset) { _, row in
                                HStack(spacing: 8) {
                                    Text("\(row.route) · \(row.destination)")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(row.eta)
                                        .font(.system(size: 12, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundColor(Color(.systemGray))
                                }
                            }
                        }
                    } else if pinned {
                        HStack(spacing: 9) {
                            Text(context.attributes.fromStation)
                                .font(.system(size: 11))
                                .foregroundColor(Color(.systemGray))
                                .lineLimit(1)
                            ProgressView(value: context.state.progressPercent)
                                .tint(.white)
                                .background(Color(white: 0.25))
                                .clipShape(Capsule())
                            Text("往 \(context.state.alightStation ?? context.state.nextStation)"
                                 + (context.state.remainingStops.map { "・還剩 \($0) 站" } ?? ""))
                                .font(.system(size: 11))
                                .foregroundColor(Color(.systemGray))
                                .lineLimit(1)
                        }
                    } else if waiting {
                        Text("於 \(context.attributes.fromStation) 上車"
                             + (context.state.walkMinutes > 0
                                ? "・步行 \(context.state.walkMinutes) 分"
                                : ""))
                            .font(.system(size: 12))
                            .foregroundColor(Color(.systemGray))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                    } else {
                        HStack(spacing: 9) {
                            Text(context.attributes.fromStation)
                                .font(.system(size: 11))
                                .foregroundColor(Color(.systemGray))
                                .lineLimit(1)
                            ProgressView(value: context.state.progressPercent)
                                .tint(.white)
                                .background(Color(white: 0.25))
                                .clipShape(Capsule())
                            Text(context.state.alightStation ?? context.state.nextStation)
                                .font(.system(size: 11))
                                .foregroundColor(Color(.systemGray))
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                if board {
                    Text(boardRows.first?.route ?? "")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                } else if pinned {
                    Text(context.state.routeNumber ?? context.attributes.routeOrTrain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                } else {
                    Image(systemName: glyph)
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                }
            } compactTrailing: {
                if board {
                    Text(boardRows.first?.eta ?? "")
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .frame(maxWidth: 48)
                        .lineLimit(1)
                } else if pinned {
                    if let eta = context.state.etaDate, eta > Date() {
                        Text(timerInterval: Date()...eta, countsDown: true)
                            .font(.system(size: 14, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .frame(maxWidth: 48)
                    } else {
                        Text("進站中")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                } else if waiting {
                    if let eta = context.state.etaDate, eta > Date() {
                        Text(timerInterval: Date()...eta, countsDown: true)
                            .font(.system(size: 14, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .frame(maxWidth: 48)
                    } else {
                        Text("進站中")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                } else {
                    Text("剩 \(context.state.remainingStops ?? 0) 站")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            } minimal: {
                if board {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                } else if pinned {
                    _CircularProgress(value: context.state.progressPercent)
                } else if waiting {
                    if let eta = context.state.etaDate, eta > Date() {
                        Text("\(minutesUntil(eta))分")
                            .font(.system(size: 11, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: glyph)
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                    }
                } else {
                    _CircularProgress(value: context.state.progressPercent)
                }
            }
        }
    }
}

/// True when the state carries a pinned vehicle (追蹤), overriding the
/// MaaS waiting/riding presentation regardless of `mode`.
private func isPinned(_ state: BusLiveActivityAttributes.ContentState) -> Bool {
    !(state.plate ?? "").isEmpty
}

/// Lock-screen card for `mode == "board"`: a stop header plus its route
/// rows, soonest first. No 車況 and no progress bar — a board lists many
/// routes, so there is no single destination to draw progress toward.
@available(iOS 16.1, *)
private struct BoardCard: View {
    let context: ActivityViewContext<BusLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "signpost.right.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                Text(context.state.stopName ?? "")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array((context.state.routes ?? []).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        Text("\(row.route) · \(row.destination)")
                            .font(.system(size: 14))
                            .lineLimit(1)
                        Spacer()
                        Text(row.eta)
                            .font(.system(size: 14, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
    }
}

@available(iOS 16.1, *)
private struct RidingCard: View {
    let context: ActivityViewContext<BusLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: typeGlyph(context.attributes.type))
                .font(.system(size: 36))
                .foregroundColor(.primary)
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.routeOrTrain)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Text("下一站 \(context.state.nextStation)")
                    .font(.system(size: 16, weight: .semibold))
                HStack(spacing: 8) {
                    Text(context.attributes.fromStation)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    ProgressView(value: context.state.progressPercent)
                        .tint(.primary)
                    Text(context.state.alightStation ?? context.state.nextStation)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                // Trailing block folded into a single caption line keeps the
                // card uncluttered on narrow lock-screen widths.
                Text("\(context.state.alightStation ?? "") 下車・剩 \(context.state.remainingStops ?? 0) 站")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
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
            Image(systemName: typeGlyph(context.attributes.type))
                .font(.system(size: 36))
                .foregroundColor(.primary)
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
                    .frame(width: 76)
            } else {
                Text("進站中")
                    .font(.system(size: 18, weight: .semibold))
            }
        }
        .padding(16)
    }
}

@available(iOS 16.1, *)
private struct PinnedCard: View {
    let context: ActivityViewContext<BusLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: typeGlyph(context.attributes.type))
                .font(.system(size: 36))
                .foregroundColor(.primary)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(context.state.routeNumber ?? context.attributes.routeOrTrain)・\(context.state.plate ?? "")")
                    .font(.system(size: 16, weight: .semibold))
                Text("往 \(context.state.alightStation ?? context.state.nextStation)"
                     + (context.state.remainingStops.map { "・還剩 \($0) 站" } ?? ""))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                ProgressView(value: context.state.progressPercent)
                    .tint(.primary)
            }
            Spacer()
            if let eta = context.state.etaDate, eta > Date() {
                // Self-ticking: no channel update needed per second.
                Text(timerInterval: Date()...eta, countsDown: true)
                    .font(.system(size: 24, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 76)
            } else {
                Text("進站中")
                    .font(.system(size: 18, weight: .semibold))
            }
        }
        .padding(16)
    }
}

/// Monochrome progress ring for the minimal riding presentation.
/// White arc over a 20%-white track; no percentage label, no accent color.
private struct _CircularProgress: View {
    let value: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: value)
                .stroke(Color.white, lineWidth: 3)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 24, height: 24)
    }
}
