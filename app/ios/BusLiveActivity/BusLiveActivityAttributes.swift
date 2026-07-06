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
    }

    let routeOrTrain: String
    let fromStation: String
    let toStation: String
    let type: String
}
