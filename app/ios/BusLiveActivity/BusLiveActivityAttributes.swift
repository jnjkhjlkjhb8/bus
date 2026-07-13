import ActivityKit
import Foundation

struct BusLiveActivityAttributes: ActivityAttributes {
    /// One row of a station ETA board: route/train number, its destination,
    /// and the formatted ETA label (already sorted soonest-first by Dart).
    struct BoardRow: Codable, Hashable {
        let route: String
        let destination: String
        let eta: String
    }

    struct ContentState: Codable, Hashable {
        /// "waiting" | "riding" | "board"
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
        /// board mode only: the stop this board is for, and its rows.
        var stopName: String?
        var routes: [BoardRow]?
    }

    let routeOrTrain: String
    let fromStation: String
    let toStation: String
    let type: String
}
