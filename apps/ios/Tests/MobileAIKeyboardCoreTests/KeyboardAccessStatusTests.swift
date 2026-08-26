import XCTest
@testable import MobileAIKeyboardCore

final class KeyboardAccessStatusTests: XCTestCase {
    func testStatusRoundTripsWithoutContentFields() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let status = KeyboardAccessStatus(fullAccessEnabled: true, appGroupAvailable: true, checkedAt: date)
        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(KeyboardAccessStatus.self, from: data)

        XCTAssertEqual(decoded, status)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("text"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("prompt"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("token"))
    }

    func testStatusStoreDoesNotClaimSharedAppGroupWhenUnavailable() {
        let store = AppGroupKeyboardAccessStatusStore()
        if !store.isUsingSharedAppGroup {
            XCTAssertNil(store.load())
        }
    }

    func testStatusFreshnessRejectsFutureAndExpiredObservations() {
        let status = KeyboardAccessStatus(fullAccessEnabled: true, appGroupAvailable: true, checkedAt: Date(timeIntervalSince1970: 1_000))
        XCTAssertTrue(status.isFresh(at: Date(timeIntervalSince1970: 1_299), maximumAge: 300))
        XCTAssertFalse(status.isFresh(at: Date(timeIntervalSince1970: 1_301), maximumAge: 300))
        XCTAssertFalse(status.isFresh(at: Date(timeIntervalSince1970: 999), maximumAge: 300))
    }
}
