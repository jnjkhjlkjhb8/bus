import ActivityKit
import Foundation

/// One alight-tracking session, as the Live Activity sees it.
///
/// Mirrors Dart's `AlightTrackContent` field for field. Bus, TRA, THSR and
/// metro all speak this one vocabulary, so the card cannot drift per mode —
/// which is the whole reason the four per-surface layouts that used to live
/// here were replaced by one.
struct AlightTrackAttributes: ActivityAttributes {
    /// Which network. Selects the leading glyph, and nothing else.
    enum Mode: String, Codable, Hashable {
        case bus, tra, thsr, metro

        /// All four glyphs exist on iOS 16, so no availability guard is needed.
        /// TRA and THSR share the rail glyph: the card's own text already says
        /// which train, and at badge size the useful distinction is
        /// rail-versus-bus-versus-metro.
        var glyph: String {
            switch self {
            case .bus: return "bus.fill"
            case .metro: return "tram.fill"
            case .tra, .thsr: return "train.side.front.car"
            }
        }
    }

    /// Where the rider is in one session. Drives copy and colour; never layout.
    enum Phase: String, Codable, Hashable {
        case waiting, riding, approaching, arrived, lost

        /// A live session still has something to cancel and something to show
        /// a progress bar for. `arrived` and `lost` are terminal readings.
        var isLive: Bool {
            self == .waiting || self == .riding || self == .approaching
        }
    }

    struct ContentState: Codable, Hashable {
        var phase: Phase

        /// Route or train identity as the rider reads it: `307`, `自強 408`,
        /// `高鐵 663`, `板南線`.
        var vehicleLabel: String

        /// The specific vehicle — plate, or the metro carID. Nil when the
        /// session tracks a route rather than one vehicle.
        var vehicleId: String?

        var nextStation: String

        /// Hops from the board stop to the alight stop. At least 1, so the
        /// progress bar never divides by nothing.
        var hopCount: Int
        var currentIndex: Int
        var remainingStops: Int

        /// The rider's own 提前站數. Doubles as the colour threshold: the card
        /// turns warm at the same count the reminder fires on.
        var leadStops: Int

        /// Absolute arrival time, unix seconds. Not rendered: it sets the
        /// waiting card's stale window, which is the arrival it names.
        ///
        /// It used to drive a self-ticking `Text(timerInterval:)`. iOS renders
        /// that as `4:––` on a locked screen — it withholds the seconds — and a
        /// locked screen is where this card spends most of its life.
        ///
        /// Unix seconds rather than a `Date` because this struct is also the
        /// wire format of a server-pushed refresh (ADR-0018), which ActivityKit
        /// decodes with a plain `JSONDecoder`. A bare number would be read as
        /// seconds since 2001, and a 31-year skew is not something a card would
        /// visibly fail on until a rider read it.
        var etaUnix: Int?

        /// The arrival as the minutes the backend actually reported, printed
        /// verbatim. Deriving minutes from [etaDate] against the device clock
        /// would move the number on every re-render with no new data behind it,
        /// which reads as a countdown the feed is not backing. Android prints
        /// the same field for the same reason.
        var etaMinutes: Int?

        /// Walk to the board stop, minutes. Only meaningful while waiting.
        var walkMinutes: Int

        /// The metro line's identity as data: roundel code and colour.
        var lineCode: String?
        var lineColorHex: String?

        /// When this reading was taken, unix seconds. Read only once the system
        /// has marked the activity stale, where the exact distance is the useful
        /// part of the answer. Unix seconds for the same reason as [etaUnix].
        var asOfUnix: Int
    }

    let mode: Mode
    let boardStation: String
    let targetStation: String
}

extension AlightTrackAttributes.ContentState {
    /// [asOfUnix] as a date, for the one place that renders a distance from it.
    var asOfDate: Date { Date(timeIntervalSince1970: Double(asOfUnix)) }

    /// [etaUnix] as a date, for the stale window a waiting card sets from it.
    var etaDate: Date? { etaUnix.map { Date(timeIntervalSince1970: Double($0)) } }

    /// Fraction of the ride completed, `0...1`.
    ///
    /// A waiting session sits at 0 rather than hiding the bar: an empty track
    /// reads as "this ride has not started", and keeping the row means nothing
    /// reflows at the moment the rider boards. A lost session freezes wherever
    /// it was — that position is the last true thing the card knows.
    var progress: Double {
        switch phase {
        case .waiting:
            return 0
        case .arrived:
            return 1
        case .riding, .approaching, .lost:
            let hops = Double(max(1, hopCount))
            return min(1, max(0, Double(currentIndex) / hops))
        }
    }

    /// Route and vehicle as one string: `307 KKA-1234`, or just `307` when the
    /// session is not pinned to a vehicle.
    var vehicle: String {
        guard let id = vehicleId, !id.isEmpty else { return vehicleLabel }
        return "\(vehicleLabel) \(id)"
    }
}
