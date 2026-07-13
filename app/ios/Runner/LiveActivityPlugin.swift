import Flutter
import ActivityKit

class LiveActivityPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.wheres.bus/live_activity",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(LiveActivityPlugin(), channel: channel)
    }

    private var activityID: String?

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.1, *) else { result(nil); return }
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "start":  startActivity(args: args, result: result)
        case "update": updateActivity(args: args, result: result)
        case "stop":   stopActivity(result: result)
        default:       result(FlutterMethodNotImplemented)
        }
    }

    @available(iOS 16.1, *)
    private func startActivity(args: [String: Any], result: FlutterResult) {
        let attrs = BusLiveActivityAttributes(
            routeOrTrain: args["routeOrTrain"] as? String ?? "",
            fromStation: args["fromStation"] as? String ?? "",
            toStation: args["alightStation"] as? String ?? "",
            type: args["type"] as? String ?? "tra"
        )
        do {
            let activity = try Activity<BusLiveActivityAttributes>.request(
                attributes: attrs,
                contentState: contentState(from: args),
                pushType: nil
            )
            activityID = activity.id
            result(activity.id)
        } catch {
            result(FlutterError(code: "LA_START_FAILED",
                                message: error.localizedDescription,
                                details: nil))
        }
    }

    @available(iOS 16.1, *)
    private func updateActivity(args: [String: Any], result: FlutterResult) {
        guard let id = activityID,
              let activity = Activity<BusLiveActivityAttributes>.activities.first(where: { $0.id == id })
        else { result(nil); return }
        Task {
            await activity.update(using: contentState(from: args))
            result(nil)
        }
    }

    @available(iOS 16.1, *)
    private func stopActivity(result: FlutterResult) {
        guard let id = activityID,
              let activity = Activity<BusLiveActivityAttributes>.activities.first(where: { $0.id == id })
        else { result(nil); return }
        Task {
            await activity.end(using: nil, dismissalPolicy: .immediate)
            activityID = nil
            result(nil)
        }
    }

    @available(iOS 16.1, *)
    private func contentState(from args: [String: Any]) -> BusLiveActivityAttributes.ContentState {
        let ms = (args["etaMs"] as? Int) ?? (args["arrivalTimeMs"] as? Int) ?? 0
        return BusLiveActivityAttributes.ContentState(
            mode: args["mode"] as? String ?? "riding",
            nextStation: args["nextStation"] as? String ?? "",
            previousStation: args["previousStation"] as? String,
            alightStation: args["alightStation"] as? String,
            remainingStops: args["remainingStops"] as? Int,
            progressPercent: args["progressPercent"] as? Double ?? 0.0,
            etaDate: ms > 0 ? Date(timeIntervalSince1970: Double(ms) / 1000) : nil,
            walkMinutes: args["walkMinutes"] as? Int ?? 0,
            plate: args["plate"] as? String,
            routeNumber: args["routeNumber"] as? String
        )
    }
}
