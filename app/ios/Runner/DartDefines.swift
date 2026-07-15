import Foundation

/// Decodes Flutter's `--dart-define` values and exposes the ones the native
/// iOS layer needs (currently just the Google Maps API key).
///
/// Flutter's build tooling passes `DART_DEFINES` as a comma-separated list of
/// base64-encoded `KEY=VALUE` pairs. `Flutter/extract_dart_defines.sh` runs
/// as an Xcode "Run Script" build phase and mirrors that decoding to
/// populate `Flutter/Dart-Defines.xcconfig`, which `Debug.xcconfig` /
/// `Release.xcconfig` include so `$(GOOGLE_MAPS_API_KEY)` in `Info.plist`
/// resolves at build time. `decode(_:)` below re-implements the same parsing
/// in Swift purely so it is covered by XCTest; `mapsAPIKey(from:failClosed:)`
/// reads the build-time-resolved value back out of the app bundle at
/// runtime.
enum DartDefines {
    /// Parses a raw `DART_DEFINES` string into a `[KEY: VALUE]` map,
    /// mirroring `extract_dart_defines.sh`: comma-separated, each item
    /// base64-encoded as `KEY=VALUE`. Entries whose key starts with
    /// "flutter" (case-insensitive) are Flutter-internal build settings and
    /// are dropped, matching the shell script.
    static func decode(_ rawDartDefines: String) -> [String: String] {
        guard !rawDartDefines.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for item in rawDartDefines.split(separator: ",", omittingEmptySubsequences: true) {
            guard let data = Data(base64Encoded: String(item)),
                  let decoded = String(data: data, encoding: .utf8)
            else { continue }
            guard let separatorIndex = decoded.firstIndex(of: "=") else { continue }
            let key = String(decoded[decoded.startIndex..<separatorIndex])
            let value = String(decoded[decoded.index(after: separatorIndex)...])
            if key.lowercased().hasPrefix("flutter") { continue }
            result[key] = value
        }
        return result
    }

    /// Whether a missing Maps key must hard-fail this build rather than
    /// silently render a blank map. Debug builds (local development,
    /// simulator) are allowed to run without a key configured.
    static func isFailClosed(isDebug: Bool = _isDebugAssertConfiguration()) -> Bool {
        !isDebug
    }

    /// Extracts the Maps key from an Info.plist-style dictionary with no
    /// fail-closed side effect, so callers (and tests) can decide what to do
    /// when it is absent.
    ///
    /// - Parameter infoDictionary: the bundle's resolved Info.plist
    ///   dictionary (`Bundle.main.infoDictionary` in production).
    /// - Returns: the trimmed, non-empty API key, or `nil` when absent or
    ///   blank.
    static func resolvedMapsAPIKey(from infoDictionary: [String: Any]?) -> String? {
        let key = (infoDictionary?["GOOGLE_MAPS_API_KEY"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return key.isEmpty ? nil : key
    }

    /// Resolves the Google Maps API key this build was configured with.
    ///
    /// - Parameters:
    ///   - infoDictionary: the bundle's resolved Info.plist dictionary
    ///     (`Bundle.main.infoDictionary` in production).
    ///   - failClosed: when `true`, a missing/empty key is a build
    ///     configuration error that must stop the app rather than fail
    ///     silently with a blank map. Pass `isFailClosed()` in production.
    /// - Returns: the non-empty API key, or an empty string when the key is
    ///   absent and `failClosed` is `false`.
    static func mapsAPIKey(
        from infoDictionary: [String: Any]?,
        failClosed: Bool
    ) -> String {
        if let key = resolvedMapsAPIKey(from: infoDictionary) {
            return key
        }
        if failClosed {
            fatalError(
                "GOOGLE_MAPS_API_KEY is missing from Info.plist. Pass " +
                "--dart-define=GOOGLE_MAPS_API_KEY=... when building (see app/env/*.json) " +
                "so Flutter/extract_dart_defines.sh can bridge it into Dart-Defines.xcconfig."
            )
        }
        return ""
    }
}
