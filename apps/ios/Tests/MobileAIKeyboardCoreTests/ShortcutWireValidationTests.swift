import Foundation
import XCTest
@testable import MobileAIKeyboardCore

final class ShortcutWireValidationTests: XCTestCase {
    // MOBILE_AI_KEYBOARD_SHORTCUT_GOLDEN_CONSUMER_V1: authoritative fixture consumer.
    func testAuthoritativeRootGoldenFixtureIsConsumedByNativeValidator() throws {
        let fixtureURL = try locateRepositoryFixture()
        let fixtureData = try Data(contentsOf: fixtureURL)
        let fixture = try XCTUnwrap(try JSONSerialization.jsonObject(with: fixtureData) as? [String: Any])
        XCTAssertEqual(fixture["schema_version"] as? String, "mobile-ai-keyboard.shortcut-golden.v1")
        XCTAssertEqual(fixture["authority"] as? String, "typescript-contracts")
        let nativeStatus = try XCTUnwrap(fixture["native_consumption_status"] as? String)
        XCTAssertTrue(["not_proven", "native_unit_consumers"].contains(nativeStatus), "unknown native consumption status: \(nativeStatus)")

        let vectors = try XCTUnwrap(fixture["vectors"] as? [[String: Any]])
        XCTAssertEqual(vectors.count, 7)
        var seenIDs = Set<String>()

        for vector in vectors {
            let id = try XCTUnwrap(vector["id"] as? String)
            XCTAssertTrue(seenIDs.insert(id).inserted, "duplicate golden vector id: \(id)")
            XCTAssertEqual(vector["kind"] as? String, "shortcut_snapshot")
            let input = try XCTUnwrap(vector["input"] as? [String: Any])
            let expected = try XCTUnwrap(vector["expected"] as? [String: Any])
            let inputData = try JSONSerialization.data(withJSONObject: input, options: [])
            let report = ShortcutWireValidator.inspect(inputData, expectedDeviceID: "dev_1234567890abcdef")

            XCTAssertEqual(report.contractValid, expected["contract_valid"] as? Bool, id)
            XCTAssertEqual(report.goldenContentDigest, expected["content_digest"] as? String, id)
            XCTAssertEqual(report.rejection?.rawValue, expected["rejection"] as? String, id)

            if report.contractValid {
                XCTAssertEqual(report.computedContentDigest, input["content_digest"] as? String, id)
                let snapshot = try ShortcutWireValidator.decodeSnapshot(inputData, expectedDeviceID: "dev_1234567890abcdef")
                XCTAssertEqual(snapshot.deviceID, "dev_1234567890abcdef", id)
                XCTAssertEqual(snapshot.contentDigest, report.computedContentDigest, id)
            } else {
                XCTAssertThrowsError(try ShortcutWireValidator.decodeSnapshot(inputData, expectedDeviceID: "dev_1234567890abcdef"), id)
            }
        }
        XCTAssertEqual(seenIDs, [
            "valid_local_snapshot",
            "schema_version_rejects_unknown_version",
            "key_normalization_rejects_lowercase_physical_key",
            "digest_rejects_tampered_content",
            "duplicate_physical_key_conflict_rejects_distinct_bindings",
            "local_route_authority_rejects_host_handoff",
            "local_route_authority_rejects_tools"
        ])
    }

    func testCanonicalWireDigestMatchesTypeScriptVectorWithoutNativeDateProjection() throws {
        let fixtureURL = try locateRepositoryFixture()
        let fixture = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
        let vectors = try XCTUnwrap(fixture["vectors"] as? [[String: Any]])
        let valid = try XCTUnwrap(vectors.first(where: { $0["id"] as? String == "valid_local_snapshot" }))
        let input = try XCTUnwrap(valid["input"] as? [String: Any])
        let unsignedDigest = try ShortcutWireValidator.contentDigest(for: input)
        XCTAssertEqual(unsignedDigest, input["content_digest"] as? String)

        var reordered = input
        let bindings = try XCTUnwrap(input["bindings"] as? [Any])
        reordered.removeValue(forKey: "bindings")
        reordered["bindings"] = bindings
        XCTAssertEqual(try ShortcutWireValidator.contentDigest(for: reordered), unsignedDigest)
    }

    func testWireValidatorKeepsDistinctSecurityRejections() throws {
        let fixtureURL = try locateRepositoryFixture()
        let fixture = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
        let vectors = try XCTUnwrap(fixture["vectors"] as? [[String: Any]])
        let expected: [String: ShortcutWireRejection] = [
            "schema_version_rejects_unknown_version": .schema,
            "key_normalization_rejects_lowercase_physical_key": .keyNormalization,
            "digest_rejects_tampered_content": .digest,
            "duplicate_physical_key_conflict_rejects_distinct_bindings": .duplicateConflict,
            "local_route_authority_rejects_host_handoff": .localRouteAuthority,
            "local_route_authority_rejects_tools": .localRouteAuthority
        ]
        for vector in vectors {
            guard let id = vector["id"] as? String, let expectedRejection = expected[id], let input = vector["input"] as? [String: Any] else { continue }
            let data = try JSONSerialization.data(withJSONObject: input)
            XCTAssertEqual(ShortcutWireValidator.inspect(data).rejection, expectedRejection, id)
        }
    }

    func testWireBoundaryRejectsDuplicateMembersAndTrailingBytes() {
        let duplicateMembers = Data(#"{"schema_version":1,"schema_version":1}"#.utf8)
        XCTAssertEqual(ShortcutWireValidator.inspect(duplicateMembers).rejection, .malformed)

        let trailingBytes = Data(#"{"schema_version":1} trailing"#.utf8)
        XCTAssertEqual(ShortcutWireValidator.inspect(trailingBytes).rejection, .malformed)
    }

    private func locateRepositoryFixture() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            candidate.deleteLastPathComponent()
            let fixture = candidate.appendingPathComponent("fixtures/shortcut-golden-vectors.json")
            if FileManager.default.fileExists(atPath: fixture.path) { return fixture }
        }
        XCTFail("root fixtures/shortcut-golden-vectors.json is required but was not found")
        return URL(fileURLWithPath: "/__missing_mobile_ai_keyboard_fixture__")
    }
}
