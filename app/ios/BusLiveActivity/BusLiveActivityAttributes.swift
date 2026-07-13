import ActivityKit
import Foundation

struct BusLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "waiting" | "riding"
        var mode: String
        var nextStation: String
        var previousStation: String?
        var alightStation: String?
        var remainingStops: Int?
        var progressPercent: Double
        /// waiting: expected departure; riding: expected arrival
        var etaDate: Date?
        var walkMinutes: Int
        /// Non-empty only when a specific vehicle is pinned (追蹤); when
        /// empty, the MaaS waiting/riding views render as before.
        var plate: String?
        var routeNumber: String?
    }

    let routeOrTrain: String
    let fromStation: String
    let toStation: String
    let type: String
}
