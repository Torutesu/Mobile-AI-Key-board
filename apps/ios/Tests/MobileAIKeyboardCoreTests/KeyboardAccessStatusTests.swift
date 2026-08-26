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
}
