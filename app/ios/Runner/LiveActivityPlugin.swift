import ActivityKit
import Flutter

/// Bridges Dart's `AlightTrackChannel` to one ActivityKit Live Activity.
///
/// The whole plugin is gated on iOS 16.2 rather than the project's 16.1
/// deployment floor. 16.2 is where `ActivityContent` — and with it `staleDate`,
/// the system's own "this reading is old" mechanism — arrived, and carrying a
/// second code path for one point release would buy nothing: on 16.1 the
/// tracking card simply never appears, which is the same graceful nothing the
/// plugin already does on a device that refuses Live Activities.
class LiveActivityPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.wheres.bus/live_activity",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(LiveActivityPlugin(channel: channel), channel: channel)
    }

    private let channel: FlutterMethodChannel
    private var activityID: String?

    /// The phase the card last rendered, kept for the card itself.
    private var lastPhase: AlightTrackAttributes.Phase?

    /// Stops remaining on the previous update. A 下車提醒 alerts twice — at the
    /// 提前提醒站 and at the 下車站 — so the phase alone can no longer identify
    /// which crossing just happened: both sit inside `approaching`. The alert
    /// fires on a crossing, never on a condition, or the card would alert once
    /// per station for the rest of the ride.
    private var lastRemainingStops: Int?

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cardCancelled),
            name: .alightTrackCancelled,
            object: nil
        )
    }

    /// The 取消追蹤 button has already ended the activity; Dart still owns the
    /// session and has to hear about it to release its own lease.
    @objc private func cardCancelled() {
        activityID = nil
        lastPhase = nil
        DispatchQueue.main.async { [channel] in
            channel.invokeMethod("onCancelTrack", arguments: nil)
        }
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.2, *) else { result(nil); return }
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "start": start(args: args, result: result)
        case "update": update(args: args, result: result)
        case "stop": stop(result: result)
        default: result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Commands

    @available(iOS 16.2, *)
    private func start(args: [String: Any], result: FlutterResult) {
        let state = contentState(from: args)
        let attributes = AlightTrackAttributes(
            mode: AlightTrackAttributes.Mode(rawValue: args["mode"] as? String ?? "") ?? .bus,
            boardStation: args["boardStation"] as? String ?? "",
            targetStation: args["targetStation"] as? String ?? ""
        )
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content(state, mode: attributes.mode),
                pushType: nil
            )
            activityID = activity.id
            lastPhase = state.phase
            // Seeds the crossing baseline, so a session that opens already
            // inside a threshold does not alert for a crossing that happened
            // before the card existed.
            lastRemainingStops = state.remainingStops
            result(activity.id)
        } catch {
            result(FlutterError(
                code: "LA_START_FAILED",
                message: error.localizedDescription,
                details: nil
            ))
        }
    }

    @available(iOS 16.2, *)
    private func update(args: [String: Any], result: @escaping FlutterResult) {
        guard let activity = current() else { result(nil); return }
        let state = contentState(from: args)
        // Computed before `lastPhase` moves: the alert is a crossing, not a
        // condition.
        let alert = reminderAlert(for: state, target: activity.attributes.targetStation)
        lastPhase = state.phase
        lastRemainingStops = state.remainingStops

        // A terminal reading is ended natively with a linger rather than left
        // for Dart to dismiss on a timer: an ending has to be seen, and a timer
        // in the app cannot fire once iOS has suspended it.
        if !state.phase.isLive {
            Task {
                await activity.end(
                    content(state, mode: activity.attributes.mode),
                    dismissalPolicy: .after(Date().addingTimeInterval(Self.lingerSeconds))
                )
                result(nil)
            }
            return
        }

        Task {
            await activity.update(
                content(state, mode: activity.attributes.mode),
                alertConfiguration: alert
            )
            result(nil)
        }
    }

    @available(iOS 16.2, *)
    private func stop(result: @escaping FlutterResult) {
        guard let activity = current() else { result(nil); return }
        activityID = nil
        lastPhase = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            result(nil)
        }
    }

    @available(iOS 16.2, *)
    private func current() -> Activity<AlightTrackAttributes>? {
        guard let id = activityID else { return nil }
        return Activity<AlightTrackAttributes>.activities.first { $0.id == id }
    }

    // MARK: - Payload

    /// How long a terminal card stays on screen before the system dismisses it.
    private static let lingerSeconds: TimeInterval = 8

    @available(iOS 16.2, *)
    private func content(
        _ state: AlightTrackAttributes.ContentState,
        mode: AlightTrackAttributes.Mode
    ) -> ActivityContent<AlightTrackAttributes.ContentState> {
        ActivityContent(state: state, staleDate: staleDate(state, mode: mode))
    }

    /// When the system should start treating this reading as old.
    ///
    /// Updates are local-only, so a suspended app leaves the card frozen with
    /// no way to say so; `staleDate` is how the platform says it instead. The
    /// window is per mode because the feeds behind them are not the same
    /// cadence: bus ETA lands every 30 s, a metro card moves once per station
    /// hop, and a train can sit between two rural stations for a long time
    /// while nothing is wrong. A single number would cry stale on TRA or stay
    /// quiet far too long on a bus.
    @available(iOS 16.2, *)
    private func staleDate(
        _ state: AlightTrackAttributes.ContentState,
        mode: AlightTrackAttributes.Mode
    ) -> Date? {
        // A waiting card carries a self-ticking countdown to a fixed date, so
        // it stays true without new data right up to the arrival it names.
        if state.phase == .waiting { return state.etaDate }
        guard state.phase.isLive else { return nil }
        let window: TimeInterval
        switch mode {
        case .bus: window = 3 * 60
        case .metro: window = 6 * 60
        case .tra, .thsr: window = 20 * 60
        }
        return state.asOf.addingTimeInterval(window)
    }

    /// The two 下車提醒 alerts, each on the one update that crosses into it.
    ///
    /// ADR-0020 asks for a vibration with nothing entering the notification
    /// centre. On iOS that is not reachable: no API vibrates a backgrounded
    /// app, and an alerting Live Activity update is the closest primitive.
    /// `AlertConfiguration` offers no silent option, so on a device that is not
    /// on silent this also makes the default alert sound. That is a platform
    /// ceiling, not an unfinished seam — do not "fix" it from Dart.
    ///
    /// The long/short distinction the in-app haptics draw cannot be expressed
    /// here either, so the two events are told apart by their words instead.
    @available(iOS 16.2, *)
    private func reminderAlert(
        for state: AlightTrackAttributes.ContentState,
        target: String
    ) -> AlertConfiguration? {
        guard state.phase.isLive, let previous = lastRemainingStops else { return nil }
        let remaining = state.remainingStops
        guard remaining < previous else { return nil }
        if remaining == 1 {
            return AlertConfiguration(
                title: "Get Set",
                body: "下一站 \(target)",
                sound: .default
            )
        }
        if state.leadStops > 0, remaining == state.leadStops + 1 {
            return AlertConfiguration(
                title: "Ready",
                body: "再過 \(remaining) 站到 \(target)",
                sound: .default
            )
        }
        return nil
    }

    /// Dart's `AlightTrackContent.toArgs()`, one field at a time.
    private func contentState(from args: [String: Any]) -> AlightTrackAttributes.ContentState {
        let etaDate = (args["etaMs"] as? Int).flatMap { ms in
            ms > 0 ? Date(timeIntervalSince1970: Double(ms) / 1000) : nil
        }
        return AlightTrackAttributes.ContentState(
            phase: AlightTrackAttributes.Phase(rawValue: args["phase"] as? String ?? "") ?? .riding,
            vehicleLabel: args["vehicleLabel"] as? String ?? "",
            vehicleId: args["vehicleId"] as? String,
            nextStation: args["nextStation"] as? String ?? "",
            hopCount: max(1, args["hopCount"] as? Int ?? 1),
            currentIndex: args["currentIndex"] as? Int ?? 0,
            remainingStops: max(0, args["remainingStops"] as? Int ?? 0),
            leadStops: max(0, args["leadStops"] as? Int ?? 0),
            etaDate: etaDate,
            etaMinutes: args["etaMinutes"] as? Int,
            walkMinutes: args["walkMinutes"] as? Int ?? 0,
            lineCode: args["lineCode"] as? String,
            lineColorHex: args["lineColorHex"] as? String,
            // Stamped here rather than sent from Dart: Dart pushes an update
            // when data arrives, so the moment the command lands *is* "as of
            // when", and a field travelling over the channel could only be a
            // less accurate copy of it.
            asOf: Date()
        )
    }
}
