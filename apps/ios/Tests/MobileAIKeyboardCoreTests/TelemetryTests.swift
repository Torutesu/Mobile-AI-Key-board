import XCTest
@testable import MobileAIKeyboardCore

final class TelemetryTests: XCTestCase {
    func testTelemetryIsContentFreeAllowList() throws {
        let value = TelemetryRecorder().event(.secureFieldLocked, appVersion: "0.1", osMajorVersion: 18, locale: "ja-JP")
        let data = try JSONEncoder().encode(value)
        let serialized = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(serialized.contains("password"))
        XCTAssertFalse(serialized.contains("selection"))
        XCTAssertEqual(value.event, .secureFieldLocked)
    }
}
