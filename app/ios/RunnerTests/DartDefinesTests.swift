import XCTest

@testable import Runner

/// Covers the pure decoding/resolution logic in `DartDefines.swift`
/// (findings F07 / P0-05): the base64 comma-separated `DART_DEFINES`
/// parsing that mirrors `Flutter/extract_dart_defines.sh`, and the
/// fail-closed behavior for a missing Google Maps API key.
final class DartDefinesTests: XCTestCase {

  private func base64(_ s: String) -> String {
    Data(s.utf8).base64EncodedString()
  }

  func testDecodeParsesCommaSeparatedBase64Pairs() {
    let raw = [
      base64("GOOGLE_MAPS_API_KEY=abc123"),
      base64("SOME_OTHER_KEY=value"),
    ].joined(separator: ",")

    let decoded = DartDefines.decode(raw)

    XCTAssertEqual(decoded["GOOGLE_MAPS_API_KEY"], "abc123")
    XCTAssertEqual(decoded["SOME_OTHER_KEY"], "value")
  }

  func testDecodeDropsFlutterPrefixedKeysCaseInsensitively() {
    let raw = [
      base64("FLUTTER_ROOT=/opt/flutter"),
      base64("flutterFoo=bar"),
      base64("GOOGLE_MAPS_API_KEY=abc123"),
    ].joined(separator: ",")

    let decoded = DartDefines.decode(raw)

    XCTAssertNil(decoded["FLUTTER_ROOT"])
    XCTAssertNil(decoded["flutterFoo"])
    XCTAssertEqual(decoded["GOOGLE_MAPS_API_KEY"], "abc123")
  }

  func testDecodeIgnoresMalformedItems() {
    let raw = ["not-valid-base64!!!", base64("NO_EQUALS_SIGN")].joined(separator: ",")

    let decoded = DartDefines.decode(raw)

    XCTAssertTrue(decoded.isEmpty)
  }

  func testDecodeOfEmptyStringReturnsEmptyMap() {
    XCTAssertTrue(DartDefines.decode("").isEmpty)
  }

  func testResolvedMapsAPIKeyReturnsTrimmedValueWhenPresent() {
    let key = DartDefines.resolvedMapsAPIKey(from: ["GOOGLE_MAPS_API_KEY": "  abc123  "])
    XCTAssertEqual(key, "abc123")
  }

  func testResolvedMapsAPIKeyReturnsNilWhenMissing() {
    XCTAssertNil(DartDefines.resolvedMapsAPIKey(from: [:]))
    XCTAssertNil(DartDefines.resolvedMapsAPIKey(from: nil))
  }

  func testResolvedMapsAPIKeyReturnsNilWhenBlank() {
    XCTAssertNil(DartDefines.resolvedMapsAPIKey(from: ["GOOGLE_MAPS_API_KEY": "   "]))
  }

  func testMapsAPIKeyReturnsValueWithoutFailingClosedWhenPresent() {
    let key = DartDefines.mapsAPIKey(
      from: ["GOOGLE_MAPS_API_KEY": "abc123"],
      failClosed: true
    )
    XCTAssertEqual(key, "abc123")
  }

  /// Debug/local builds must not crash just because the key was never
  /// configured (e.g. a contributor running `flutter run` without Maps
  /// configured) — `failClosed: false` returns an empty string instead of
  /// calling `fatalError`.
  func testMapsAPIKeyReturnsEmptyWhenMissingAndNotFailClosed() {
    let key = DartDefines.mapsAPIKey(from: [:], failClosed: false)
    XCTAssertEqual(key, "")
  }

  func testIsFailClosedIsTrueWhenNotDebug() {
    XCTAssertTrue(DartDefines.isFailClosed(isDebug: false))
  }

  func testIsFailClosedIsFalseWhenDebug() {
    XCTAssertFalse(DartDefines.isFailClosed(isDebug: true))
  }
}
