import ActivityKit
import Foundation

struct BusLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var nextStation: String
        var previousStation: String?
        var progressPercent: Double
        var arrivalTime: Date
    }

    let routeOrTrain: String
    let fromStation: String
    let toStation: String
    let type: String
}
