import CryptoKit
import CoreFoundation
import Foundation

/// Rejection classes shared with the TypeScript shortcut golden vectors.
///
/// The native model is intentionally not used to classify malformed wire
/// values: Codable would report a lowercase `Keyh` as a generic decoding
/// failure, while the contract needs to preserve that as a key-normalization
/// violation. Keeping this small wire validator beside the native model makes
/// the process-boundary rules executable by both the host and the extension.
public enum ShortcutWireRejection: String, Codable, Equatable, Sendable {
    case schema
    case keyNormalization = "key_normalization"
    case digest
    case duplicateConflict = "duplicate_conflict"
    case localRouteAuthority = "local_route_authority"
    case malformed
}

public struct ShortcutWireValidationReport: Equatable, Sendable {
    public let contractValid: Bool
    /// The digest supplied by the wire value, retained for diagnostics.
    public let declaredContentDigest: String?
    /// The digest recomputed from the wire value without `content_digest`.
    public let computedContentDigest: String?
    public let rejection: ShortcutWireRejection?

    public init(contractValid: Bool, declaredContentDigest: String?, computedContentDigest: String?, rejection: ShortcutWireRejection?) {
        self.contractValid = contractValid
        self.declaredContentDigest = declaredContentDigest
        self.computedContentDigest = computedContentDigest
        self.rejection = rejection
    }

    /// The shape used by `fixtures/shortcut-golden-vectors.json`.
    public var goldenContentDigest: String? {
        contractValid ? declaredContentDigest : nil
    }
}

public enum ShortcutWireValidationError: Error, Equatable, LocalizedError, Sendable {
    case rejected(ShortcutWireRejection)
    case decoding

    public var errorDescription: String? {
        switch self {
        case .rejected(let rejection): return "shortcut wire value rejected: \(rejection.rawValue)"
        case .decoding: return "valid shortcut wire value could not be decoded into the native model"
        }
    }
}

/// Canonicalizes and validates the JSON crossing the host/keyboard boundary.
///
/// The canonical form deliberately mirrors `packages/contracts/src/canonical.ts`:
/// object keys are sorted, arrays retain order, and the `content_digest` is
/// computed over the complete unsigned wire object. The implementation accepts
/// only JSON values and never sees text entered by the user.
public enum ShortcutWireValidator {
    private static let digestPattern = "^sha256:[a-f0-9]{64}$"
    private static let idPatterns: [String: String] = [
        "snapshot_id": "^ss_[A-Za-z0-9_-]{16,128}$",
        "layout_id": "^layout_[A-Za-z0-9_-]{16,128}$",
        "binding_id": "^bind_[A-Za-z0-9_-]{16,128}$",
        "skill_id": "^skill_[A-Za-z0-9_-]{16,128}$",
        "version_id": "^sv_[A-Za-z0-9_-]{16,128}$"
    ]

    /// Returns a report instead of throwing so callers can expose a safe,
    /// content-free recovery state at the keyboard boundary.
    public static func inspect(_ data: Data, expectedDeviceID: String? = nil) -> ShortcutWireValidationReport {
        do {
            try StrictJSONIntegrityScanner.validate(data)
            guard let root = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                throw WireFailure(.schema)
            }

            // Preserve the contract's more precise diagnostic before generic
            // schema validation or native enum decoding is attempted.
            if let version = integer(root["schema_version"]), version != 1 {
                throw WireFailure(.schema)
            }
            try classifyKeyNormalization(root)
            try validateShape(root, expectedDeviceID: expectedDeviceID)

            guard let declaredDigest = root["content_digest"] as? String else {
                throw WireFailure(.schema)
            }
            var unsigned = root
            unsigned.removeValue(forKey: "content_digest")
            let canonical = try canonicalJSONString(unsigned)
            let computedDigest = ShortcutDigest.sha256(canonical)
            if declaredDigest != computedDigest {
                return ShortcutWireValidationReport(contractValid: false, declaredContentDigest: declaredDigest, computedContentDigest: computedDigest, rejection: .digest)
            }

            if hasDuplicateActivePhysicalKey(root) {
                return ShortcutWireValidationReport(contractValid: false, declaredContentDigest: declaredDigest, computedContentDigest: computedDigest, rejection: .duplicateConflict)
            }
            if hasRouteAuthorityViolation(root) {
                return ShortcutWireValidationReport(contractValid: false, declaredContentDigest: declaredDigest, computedContentDigest: computedDigest, rejection: .localRouteAuthority)
            }
            return ShortcutWireValidationReport(contractValid: true, declaredContentDigest: declaredDigest, computedContentDigest: computedDigest, rejection: nil)
        } catch let failure as WireFailure {
            return ShortcutWireValidationReport(contractValid: false, declaredContentDigest: nil, computedContentDigest: nil, rejection: failure.rejection)
        } catch {
            return ShortcutWireValidationReport(contractValid: false, declaredContentDigest: nil, computedContentDigest: nil, rejection: .malformed)
        }
    }

    /// Canonical JSON for a JSON object. This is public so independently
    /// generated platform tests can prove digest parity without copying the
    /// canonicalization algorithm into test-only code.
    public static func canonicalJSONString(_ object: [String: Any]) throws -> String {
        try canonicalJSONValue(object)
    }

    /// Computes the contract digest from an unsigned JSON object.
    public static func contentDigest(for unsignedObject: [String: Any]) throws -> String {
        var value = unsignedObject
        value.removeValue(forKey: "content_digest")
        return ShortcutDigest.sha256(try canonicalJSONString(value))
    }

    /// Validates wire authority and then projects the value into the existing
    /// native model. A malformed value never reaches the native decoder.
    public static func decodeSnapshot(_ data: Data, expectedDeviceID: String? = nil) throws -> ShortcutSnapshotV1 {
        let report = inspect(data, expectedDeviceID: expectedDeviceID)
        guard report.contractValid else {
            throw ShortcutWireValidationError.rejected(report.rejection ?? .malformed)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "invalid ISO8601 date")
            }
            return date
        }
        do {
            return try decoder.decode(ShortcutSnapshotV1.self, from: data)
        } catch {
            throw ShortcutWireValidationError.decoding
        }
    }

    private struct WireFailure: Error {
        let rejection: ShortcutWireRejection
        init(_ rejection: ShortcutWireRejection) { self.rejection = rejection }
    }

    private static func classifyKeyNormalization(_ root: [String: Any]) throws {
        guard let bindings = root["bindings"] as? [Any] else { return }
        for bindingValue in bindings {
            guard let binding = bindingValue as? [String: Any],
                  let trigger = binding["trigger_key"] as? [String: Any],
                  let keyCode = trigger["key_code"] as? String else { continue }
            // `Keyh` and similar values are semantically recognizable but not
            // canonical physical key codes. Keep this distinct from malformed
            // JSON so clients can explain and repair imported layouts.
            if keyCode.range(of: "^Key[a-z]$", options: .regularExpression) != nil {
                throw WireFailure(.keyNormalization)
            }
        }
    }

    private static func validateShape(_ root: [String: Any], expectedDeviceID: String?) throws {
        try exactKeys(root, ["schema_version", "snapshot_id", "generation", "user_subject_hash", "device_id", "layout", "bindings", "skills", "connection_states", "policy_epoch", "created_at", "expires_at", "tombstone_reason", "content_digest"])
        guard integer(root["schema_version"]) == 1,
              let snapshotID = string(root["snapshot_id"]), matches(snapshotID, idPatterns["snapshot_id"]!),
              let generation = integer(root["generation"]), generation > 0,
              let deviceID = string(root["device_id"]), validOpaque(deviceID, prefix: "dev_"),
              let layout = object(root["layout"]),
              let bindings = array(root["bindings"]), bindings.count <= 32,
              let skills = array(root["skills"]), skills.count <= 32,
              let connections = array(root["connection_states"]), connections.count <= 32,
              let policyEpoch = integer(root["policy_epoch"]), policyEpoch >= 0,
              let createdAt = string(root["created_at"]), validDate(createdAt),
              let expiresAt = root["expires_at"], (expiresAt is NSNull || (string(expiresAt) != nil && validDate(string(expiresAt)!))),
              let tombstone = root["tombstone_reason"], (tombstone is NSNull || ["signed_out", "account_deleted", "device_revoked"].contains(string(tombstone) ?? "")),
              let digest = string(root["content_digest"]), matches(digest, digestPattern) else {
            throw WireFailure(.schema)
        }
        if let expectedDeviceID, expectedDeviceID != deviceID { throw WireFailure(.schema) }
        if let userHash = root["user_subject_hash"], !(userHash is NSNull) && !(string(userHash).map { matches($0, digestPattern) } ?? false) {
            throw WireFailure(.schema)
        }
        if let expiry = string(expiresAt), let expiryDate = Date.parseISO(expiry), let createdDate = Date.parseISO(createdAt), expiryDate <= createdDate {
            throw WireFailure(.schema)
        }
        try validateLayout(layout, deviceID: deviceID)
        try validateBindings(bindings, deviceID: deviceID)
        try validateSkills(skills)
        try validateConnections(connections)
        try validateCrossReferences(root, bindings: bindings, skills: skills)
    }

    private static func validateLayout(_ layout: [String: Any], deviceID: String) throws {
        try exactKeys(layout, ["schema_version", "layout_id", "user_id", "device_id", "revision", "key_binding_ids", "palette_binding_ids", "long_press_duration_ms", "cancellation_distance", "command_position", "overflow_enabled", "updated_at"])
        guard integer(layout["schema_version"]) == 1,
              let layoutID = string(layout["layout_id"]), matches(layoutID, idPatterns["layout_id"]!),
              let userID = string(layout["user_id"]), validOpaque(userID, prefix: "usr_"),
              string(layout["device_id"]) == deviceID,
              let revision = integer(layout["revision"]), revision > 0,
              let keys = stringArray(layout["key_binding_ids"]), keys.count <= 26,
              let palette = stringArray(layout["palette_binding_ids"]), palette.count <= 32,
              integer(layout["long_press_duration_ms"]) == 450,
              let distance = number(layout["cancellation_distance"]), distance == 10 || distance == 12,
              string(layout["command_position"]) == "leading",
              bool(layout["overflow_enabled"]) == true,
              let updatedAt = string(layout["updated_at"]), validDate(updatedAt),
              Set(keys).count == keys.count, Set(palette).count == palette.count else {
            throw WireFailure(.schema)
        }
        guard keys.allSatisfy({ matches($0, idPatterns["binding_id"]!) }), palette.allSatisfy({ matches($0, idPatterns["binding_id"]!) }) else { throw WireFailure(.schema) }
    }

    private static func validateBindings(_ values: [Any], deviceID: String) throws {
        guard Set(values.compactMap({ ($0 as? [String: Any])?["binding_id"] as? String })).count == values.count else { throw WireFailure(.schema) }
        for value in values {
            guard let binding = object(value) else { throw WireFailure(.schema) }
            try exactKeys(binding, ["schema_version", "binding_id", "user_id", "device_id", "skill_id", "version_id", "skill_version", "skill_digest", "trigger_key", "presentation", "enabled", "local_eligibility", "required_connection_ids", "created_at", "updated_at"])
            guard integer(binding["schema_version"]) == 1,
                  let bindingID = string(binding["binding_id"]), matches(bindingID, idPatterns["binding_id"]!),
                  let userID = string(binding["user_id"]), validOpaque(userID, prefix: "usr_"),
                  string(binding["device_id"]) == deviceID,
                  let skillID = string(binding["skill_id"]), matches(skillID, idPatterns["skill_id"]!),
                  let versionID = string(binding["version_id"]), matches(versionID, idPatterns["version_id"]!),
                  let skillVersion = integer(binding["skill_version"]), skillVersion > 0,
                  let skillDigest = string(binding["skill_digest"]), matches(skillDigest, digestPattern),
                  let trigger = object(binding["trigger_key"]),
                  let presentation = object(binding["presentation"]),
                  bool(binding["enabled"]) != nil,
                  ["local", "connected_read", "confirmed_write"].contains(string(binding["local_eligibility"])),
                  let connections = stringArray(binding["required_connection_ids"]), connections.count <= 5, Set(connections).count == connections.count,
                  let createdAt = string(binding["created_at"]), validDate(createdAt),
                  let updatedAt = string(binding["updated_at"]), validDate(updatedAt),
                  let createdDate = Date.parseISO(createdAt), let updatedDate = Date.parseISO(updatedAt), updatedDate >= createdDate else {
                throw WireFailure(.schema)
            }
            try validateTrigger(trigger)
            try validatePresentation(presentation)
            guard connections.allSatisfy({ validOpaqueConnection($0) }) else { throw WireFailure(.schema) }
        }
    }

    private static func validateTrigger(_ trigger: [String: Any]) throws {
        try exactKeys(trigger, ["layout_id", "key_code", "display_label", "activation_gesture"])
        guard string(trigger["layout_id"]) == "latin_qwerty_v1",
              let keyCode = string(trigger["key_code"]), keyCode.range(of: "^Key[A-Z]$", options: .regularExpression) != nil,
              let label = string(trigger["display_label"]), label.range(of: "^[A-Z]$", options: .regularExpression) != nil,
              label == String(keyCode.suffix(1)), string(trigger["activation_gesture"]) == "long_press" else {
            throw WireFailure(.schema)
        }
    }

    private static func validatePresentation(_ presentation: [String: Any]) throws {
        try exactKeys(presentation, ["icon_kind", "icon_value", "short_label", "accessibility_label", "accessibility_hint", "tint_token"])
        guard let iconKind = string(presentation["icon_kind"]), ["system", "text"].contains(iconKind),
              let iconValue = string(presentation["icon_value"]), !iconValue.isEmpty,
              let shortLabel = string(presentation["short_label"]), safeText(shortLabel), Array(shortLabel).count <= 24,
              let accessibilityLabel = string(presentation["accessibility_label"]), safeText(accessibilityLabel), Array(accessibilityLabel).count >= 2, Array(accessibilityLabel).count <= 80,
              let accessibilityHint = string(presentation["accessibility_hint"]), safeText(accessibilityHint), Array(accessibilityHint).count <= 160,
              ["neutral", "accent", "read", "write"].contains(string(presentation["tint_token"])) else { throw WireFailure(.schema) }
        if iconKind == "system" {
            guard iconValue.range(of: "^[a-z][a-z0-9_.-]{1,79}$", options: .regularExpression) != nil else { throw WireFailure(.schema) }
        } else if Array(iconValue).count > 3 || iconValue.range(of: "[\\u0000-\\u001f\\u007f]", options: .regularExpression) != nil {
            throw WireFailure(.schema)
        }
    }

    private static func validateSkills(_ values: [Any]) throws {
        var identities = Set<String>()
        for value in values {
            guard let skill = object(value) else { throw WireFailure(.schema) }
            try exactKeys(skill, ["skill_id", "version_id", "skill_version", "skill_digest", "name", "description", "input_sources", "output_type", "risk_ceiling", "confirmation", "retention", "tool_summaries", "execution_route"])
            guard let skillID = string(skill["skill_id"]), matches(skillID, idPatterns["skill_id"]!),
                  let versionID = string(skill["version_id"]), matches(versionID, idPatterns["version_id"]!),
                  let version = integer(skill["skill_version"]), version > 0,
                  let digest = string(skill["skill_digest"]), matches(digest, digestPattern),
                  let name = string(skill["name"]), safeText(name),
                  let description = string(skill["description"]), safeText(description),
                  let sources = stringArray(skill["input_sources"]), sources.count <= 7, Set(sources).count == sources.count,
                  ["insert_text", "replace_selection", "copy", "json"].contains(string(skill["output_type"])),
                  ["R0", "R1", "R2", "R3"].contains(string(skill["risk_ceiling"])),
                  ["none", "policy_required"].contains(string(skill["confirmation"])),
                  ["none", "transient_content", "receipt_metadata"].contains(string(skill["retention"])),
                  let tools = array(skill["tool_summaries"]), tools.count <= 16,
                  ["keyboard_local", "keyboard_network", "host_handoff"].contains(string(skill["execution_route"])) else { throw WireFailure(.schema) }
            guard sources.allSatisfy({ ["command", "selection", "surrounding_text", "clipboard", "current_datetime", "locale", "location"].contains($0) }) else { throw WireFailure(.schema) }
            let identity = "\(skillID)|\(versionID)"
            guard identities.insert(identity).inserted else { throw WireFailure(.schema) }
            for toolValue in tools {
                guard let tool = object(toolValue) else { throw WireFailure(.schema) }
                try exactKeys(tool, ["operation", "required_scopes", "side_effect"])
                guard let operation = string(tool["operation"]), operation.range(of: "^[a-z][a-z0-9_.-]{2,100}$", options: .regularExpression) != nil,
                      let scopes = stringArray(tool["required_scopes"]), scopes.count <= 5,
                      scopes.allSatisfy({ $0.range(of: "^[a-z][a-z0-9_.-]{2,100}$", options: .regularExpression) != nil }),
                      ["none", "creates_private_event", "updates_private_resource"].contains(string(tool["side_effect"])) else { throw WireFailure(.schema) }
            }
        }
    }

    private static func validateConnections(_ values: [Any]) throws {
        var ids = Set<String>()
        for value in values {
            guard let connection = object(value), Set(connection.keys) == Set(["connection_id", "state", "epoch"]),
                  let id = string(connection["connection_id"]), validOpaqueConnection(id), ids.insert(id).inserted,
                  ["active", "expired", "revoked", "missing"].contains(string(connection["state"])),
                  let epoch = integer(connection["epoch"]), epoch >= 0 else { throw WireFailure(.schema) }
        }
    }

    private static func validateCrossReferences(_ root: [String: Any], bindings: [Any], skills: [Any]) throws {
        let skillMap = Dictionary(uniqueKeysWithValues: skills.compactMap { value -> (String, [String: Any])? in
            guard let skill = object(value), let id = string(skill["skill_id"]), let version = string(skill["version_id"]) else { return nil }
            return ("\(id)|\(version)", skill)
        })
        let bindingIDs = Set(bindings.compactMap { object($0).flatMap { string($0["binding_id"]) } })
        guard let layout = object(root["layout"]), let keyIDs = stringArray(layout["key_binding_ids"]), let paletteIDs = stringArray(layout["palette_binding_ids"]),
              Set(keyIDs) == Set(bindings.compactMap { value in object(value).flatMap { bool($0["enabled"]) == true ? string($0["binding_id"]) : nil } }),
              Set(keyIDs).isSubset(of: bindingIDs), Set(paletteIDs).isSubset(of: bindingIDs) else { throw WireFailure(.schema) }
        for value in bindings {
            guard let binding = object(value), let skillID = string(binding["skill_id"]), let versionID = string(binding["version_id"]),
                  let skill = skillMap["\(skillID)|\(versionID)"], string(skill["skill_digest"]) == string(binding["skill_digest"]), integer(skill["skill_version"]) == integer(binding["skill_version"]) else { throw WireFailure(.schema) }
        }
        guard Set(skills.compactMap { object($0).flatMap { skill in string(skill["skill_id"]).map { "\($0)|\(string(skill["version_id"]) ?? "")" } } }).isSubset(of: Set(bindings.compactMap { object($0).flatMap { binding in string(binding["skill_id"]).map { "\($0)|\(string(binding["version_id"]) ?? "")" } } })) else { throw WireFailure(.schema) }
    }

    private static func hasDuplicateActivePhysicalKey(_ root: [String: Any]) -> Bool {
        guard let bindings = root["bindings"] as? [Any] else { return false }
        var keys = Set<String>()
        for value in bindings {
            guard let binding = object(value), bool(binding["enabled"]) == true, let trigger = object(binding["trigger_key"]), let key = string(trigger["key_code"]) else { continue }
            if !keys.insert(key).inserted { return true }
        }
        return false
    }

    private static func hasRouteAuthorityViolation(_ root: [String: Any]) -> Bool {
        guard let bindings = root["bindings"] as? [Any], let skills = root["skills"] as? [Any] else { return true }
        let map: [[String: Any]] = skills.compactMap { object($0) }
        for value in bindings {
            guard let binding = object(value), let skillID = string(binding["skill_id"]), let versionID = string(binding["version_id"]),
                  let skill = map.first(where: { string($0["skill_id"]) == skillID && string($0["version_id"]) == versionID }),
                  let eligibility = string(binding["local_eligibility"]), let route = string(skill["execution_route"]),
                  let tools = array(skill["tool_summaries"]), let connections = stringArray(binding["required_connection_ids"]), let risk = string(skill["risk_ceiling"]), let confirmation = string(skill["confirmation"]) else { return true }
            let sideEffect = tools.contains { object($0).flatMap { string($0["side_effect"]) }.map { $0 != "none" } == true }
            switch eligibility {
            case "local":
                if route != "keyboard_local" || !tools.isEmpty || !connections.isEmpty || !["R0", "R1"].contains(risk) { return true }
            case "connected_read":
                if route == "keyboard_local" || tools.isEmpty || sideEffect || connections.isEmpty || risk == "R3" { return true }
            case "confirmed_write":
                if route == "keyboard_local" || !sideEffect || confirmation != "policy_required" || connections.isEmpty || risk != "R3" { return true }
            default: return true
            }
        }
        return false
    }

    private static func exactKeys(_ object: [String: Any], _ expected: Set<String>) throws {
        guard Set(object.keys) == expected else { throw WireFailure(.schema) }
    }

    private static func object(_ value: Any?) -> [String: Any]? { value as? [String: Any] }
    private static func array(_ value: Any?) -> [Any]? { value as? [Any] }
    private static func string(_ value: Any?) -> String? { value as? String }
    private static func bool(_ value: Any?) -> Bool? { value as? Bool }
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.rounded() == number.doubleValue else { return nil }
        return number.intValue
    }
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }
    private static func stringArray(_ value: Any?) -> [String]? {
        guard let values = array(value) else { return nil }
        let strings = values.compactMap { string($0) }
        return strings.count == values.count ? strings : nil
    }
    private static func matches(_ value: String, _ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
    private static func validOpaque(_ value: String, prefix: String) -> Bool { value.range(of: "^\(prefix)[A-Za-z0-9_-]{16,128}$", options: .regularExpression) != nil }
    private static func validOpaqueConnection(_ value: String) -> Bool { value.range(of: "^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$", options: .regularExpression) != nil }
    private static func safeText(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.range(of: "[\\u0000-\\u001f\\u007f]", options: .regularExpression) == nil }
    private static func validDate(_ value: String) -> Bool { Date.parseISO(value) != nil }

    private static func canonicalJSONValue(_ value: Any) throws -> String {
        if value is NSNull { return "null" }
        if let value = value as? String {
            let data = try JSONSerialization.data(withJSONObject: [value], options: [])
            guard let encoded = String(data: data, encoding: .utf8) else { throw WireFailure(.malformed) }
            return String(encoded.dropFirst().dropLast())
        }
        if let value = value as? NSNumber {
            guard CFGetTypeID(value) != CFBooleanGetTypeID() else { return value.boolValue ? "true" : "false" }
            let data = try JSONSerialization.data(withJSONObject: [value], options: [])
            guard let encoded = String(data: data, encoding: .utf8) else { throw WireFailure(.malformed) }
            return String(encoded.dropFirst().dropLast())
        }
        if let value = value as? Bool { return value ? "true" : "false" }
        if let value = value as? [Any] {
            return "[" + (try value.map { try canonicalJSONValue($0) }).joined(separator: ",") + "]"
        }
        if let value = value as? [String: Any] {
            let entries = value.keys.sorted { lhs, rhs in lhs.utf16.lexicographicallyPrecedes(rhs.utf16) }
            return "{" + (try entries.map { key in
                let keyJSON = try canonicalJSONValue(key)
                return "\(keyJSON):\(try canonicalJSONValue(value[key]!))"
            }).joined(separator: ",") + "}"
        }
        throw WireFailure(.malformed)
    }
}

private extension Date {
    static func parseISO(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)
        }()
    }
}

/// Foundation's JSON parser correctly rejects trailing bytes but accepts a
/// duplicate object member by keeping the last value. The wire boundary must
/// fail closed for both cases, so this small syntax scanner runs before
/// JSONSerialization and preserves duplicate-key detection without retaining
/// user content.
private struct StrictJSONIntegrityScanner {
    private var bytes: [UInt8]
    private var index = 0

    private init(_ data: Data) { bytes = Array(data) }

    static func validate(_ data: Data) throws {
        var scanner = StrictJSONIntegrityScanner(data)
        try scanner.document()
    }

    private mutating func document() throws {
        whitespace()
        try value()
        whitespace()
        guard index == bytes.count else { throw Error.invalid }
    }

    private mutating func value() throws {
        whitespace()
        guard let byte = peek else { throw Error.invalid }
        switch byte {
        case 0x22: _ = try string()
        case 0x7B: try object()
        case 0x5B: try array()
        case 0x74: try literal(Array("true".utf8))
        case 0x66: try literal(Array("false".utf8))
        case 0x6E: try literal(Array("null".utf8))
        case 0x2D, 0x30...0x39: try number()
        default: throw Error.invalid
        }
    }

    private mutating func object() throws {
        try consume(0x7B)
        whitespace()
        var keys = Set<String>()
        if consumeIf(0x7D) { return }
        while true {
            whitespace()
            guard peek == 0x22 else { throw Error.invalid }
            let key = try string()
            guard keys.insert(key).inserted else { throw Error.duplicateKey }
            whitespace(); try consume(0x3A)
            try value()
            whitespace()
            if consumeIf(0x7D) { return }
            try consume(0x2C)
        }
    }

    private mutating func array() throws {
        try consume(0x5B)
        whitespace()
        if consumeIf(0x5D) { return }
        while true {
            try value()
            whitespace()
            if consumeIf(0x5D) { return }
            try consume(0x2C)
        }
    }

    private mutating func string() throws -> String {
        try consume(0x22)
        var scalars = String.UnicodeScalarView()
        while let byte = peek {
            index += 1
            switch byte {
            case 0x22: return String(scalars)
            case 0x5C:
                guard let escape = peek else { throw Error.invalid }
                index += 1
                switch escape {
                case 0x22: scalars.append("\"")
                case 0x5C: scalars.append("\\")
                case 0x2F: scalars.append("/")
                case 0x62: scalars.append("\u{8}")
                case 0x66: scalars.append("\u{c}")
                case 0x6E: scalars.append("\n")
                case 0x72: scalars.append("\r")
                case 0x74: scalars.append("\t")
                case 0x75:
                    guard index + 4 <= bytes.count else { throw Error.invalid }
                    var scalarValue: UInt32 = 0
                    for _ in 0..<4 {
                        guard let hex = Self.hexValue(bytes[index]) else { throw Error.invalid }
                        scalarValue = scalarValue * 16 + hex
                        index += 1
                    }
                    guard let scalar = UnicodeScalar(scalarValue) else { throw Error.invalid }
                    scalars.append(scalar)
                default: throw Error.invalid
                }
            case 0x00...0x1F: throw Error.invalid
            default:
                // JSON strings are UTF-8. Appending one scalar at a time is
                // unnecessary for duplicate detection; collect the remaining
                // UTF-8 run and decode it in one operation.
                var run = [UInt8](repeating: byte, count: 1)
                while let next = peek, next >= 0x20, next != 0x22, next != 0x5C {
                    run.append(next); index += 1
                }
                guard let text = String(bytes: run, encoding: .utf8) else { throw Error.invalid }
                scalars.append(contentsOf: text.unicodeScalars)
            }
        }
        throw Error.invalid
    }

    private mutating func number() throws {
        if consumeIf(0x2D) {}
        guard let first = peek else { throw Error.invalid }
        if first == 0x30 {
            index += 1
            if let next = peek, next >= 0x30 && next <= 0x39 { throw Error.invalid }
        } else {
            guard first >= 0x31 && first <= 0x39 else { throw Error.invalid }
            while let next = peek, next >= 0x30 && next <= 0x39 { index += 1 }
        }
        if consumeIf(0x2E) {
            guard let digit = peek, digit >= 0x30 && digit <= 0x39 else { throw Error.invalid }
            while let next = peek, next >= 0x30 && next <= 0x39 { index += 1 }
        }
        if let exponent = peek, exponent == 0x65 || exponent == 0x45 {
            index += 1
            if let sign = peek, sign == 0x2B || sign == 0x2D { index += 1 }
            guard let digit = peek, digit >= 0x30 && digit <= 0x39 else { throw Error.invalid }
            while let next = peek, next >= 0x30 && next <= 0x39 { index += 1 }
        }
    }

    private mutating func literal(_ literal: [UInt8]) throws {
        guard index + literal.count <= bytes.count, Array(bytes[index..<(index + literal.count)]) == literal else { throw Error.invalid }
        index += literal.count
    }

    private mutating func consume(_ byte: UInt8) throws {
        guard consumeIf(byte) else { throw Error.invalid }
    }

    private mutating func consumeIf(_ byte: UInt8) -> Bool {
        guard peek == byte else { return false }
        index += 1
        return true
    }

    private mutating func whitespace() {
        while let byte = peek, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D { index += 1 }
    }

    private var peek: UInt8? { index < bytes.count ? bytes[index] : nil }

    private static func hexValue(_ byte: UInt8) -> UInt32? {
        switch byte {
        case 0x30...0x39: return UInt32(byte - 0x30)
        case 0x41...0x46: return UInt32(byte - 0x41 + 10)
        case 0x61...0x66: return UInt32(byte - 0x61 + 10)
        default: return nil
        }
    }

    private enum Error: Swift.Error { case invalid, duplicateKey }
}
