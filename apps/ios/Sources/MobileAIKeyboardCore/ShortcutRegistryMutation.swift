import Foundation

/// Errors returned by the pure Skill Key registry reducer.
///
/// The reducer never mutates its input. A host may therefore run a proposed
/// change (including conflict resolution) before attempting an App Group
/// publish, and retain the current snapshot if persistence fails.
public enum ShortcutRegistryMutationError: Error, Equatable, Sendable {
    case keyOccupied(ShortcutKeyCode)
    case keyIsAvailable(ShortcutKeyCode)
    case bindingNotFound
    case bindingIDAlreadyExists
    case hostHandoffUnavailable
}

/// Pure, storage-independent mutations for the physical Skill Key registry.
///
/// `assign` and `move` intentionally reject occupied keys. Callers must choose
/// `replace` or `swap` explicitly; there is no implicit overwrite path.
public enum ShortcutRegistryMutation {
    public static func assign(bindings: [ShortcutBindingV1], binding: ShortcutBindingV1) throws -> [ShortcutBindingV1] {
        try validateNewBinding(bindings: bindings, binding: binding)
        guard !bindings.contains(where: { $0.enabled && $0.keyCode == binding.keyCode }) else {
            throw ShortcutRegistryMutationError.keyOccupied(binding.keyCode)
        }
        return bindings + [binding]
    }

    /// Replace the active binding at `binding.keyCode` with `binding`.
    /// The operation is valid only when a real conflict exists, preventing a
    /// UI retry from silently taking a different path.
    public static func replace(bindings: [ShortcutBindingV1], binding: ShortcutBindingV1) throws -> [ShortcutBindingV1] {
        try validateNewBinding(bindings: bindings, binding: binding)
        guard let index = bindings.firstIndex(where: { $0.enabled && $0.keyCode == binding.keyCode }) else {
            throw ShortcutRegistryMutationError.keyIsAvailable(binding.keyCode)
        }
        guard bindings[index].id != binding.id else { throw ShortcutRegistryMutationError.bindingIDAlreadyExists }
        var result = bindings
        result.remove(at: index)
        return result + [binding]
    }

    /// Replace the owner of `key` while retaining the selected binding's ID.
    /// This is the explicit "置き換え" path when editing an existing key.
    public static func replace(bindings: [ShortcutBindingV1], bindingID: String, to key: ShortcutKeyCode) throws -> [ShortcutBindingV1] {
        guard let sourceIndex = bindings.firstIndex(where: { $0.id == bindingID }), bindings[sourceIndex].enabled else {
            throw ShortcutRegistryMutationError.bindingNotFound
        }
        guard let destinationIndex = bindings.firstIndex(where: { $0.enabled && $0.keyCode == key }) else {
            throw ShortcutRegistryMutationError.keyIsAvailable(key)
        }
        guard sourceIndex != destinationIndex else { return bindings }
        var result = bindings
        result.remove(at: destinationIndex)
        let updatedSourceIndex = sourceIndex > destinationIndex ? sourceIndex - 1 : sourceIndex
        result[updatedSourceIndex] = result[updatedSourceIndex].withKey(key)
        return result
    }

    /// Move an existing binding to an unoccupied key.
    public static func move(bindings: [ShortcutBindingV1], bindingID: String, to key: ShortcutKeyCode) throws -> [ShortcutBindingV1] {
        guard let index = bindings.firstIndex(where: { $0.id == bindingID }) else {
            throw ShortcutRegistryMutationError.bindingNotFound
        }
        guard bindings[index].enabled else { throw ShortcutRegistryMutationError.bindingNotFound }
        if let conflict = bindings.first(where: { $0.enabled && $0.keyCode == key }), conflict.id != bindingID {
            throw ShortcutRegistryMutationError.keyOccupied(key)
        }
        var result = bindings
        result[index] = result[index].withKey(key)
        return result
    }

    /// Swap the selected binding with the active owner of `key`.
    public static func swap(bindings: [ShortcutBindingV1], bindingID: String, to key: ShortcutKeyCode) throws -> [ShortcutBindingV1] {
        guard let sourceIndex = bindings.firstIndex(where: { $0.id == bindingID }), bindings[sourceIndex].enabled else {
            throw ShortcutRegistryMutationError.bindingNotFound
        }
        guard let destinationIndex = bindings.firstIndex(where: { $0.enabled && $0.keyCode == key }) else {
            throw ShortcutRegistryMutationError.keyIsAvailable(key)
        }
        guard sourceIndex != destinationIndex else { return bindings }
        let sourceKey = bindings[sourceIndex].keyCode
        var result = bindings
        result[sourceIndex] = result[sourceIndex].withKey(key)
        result[destinationIndex] = result[destinationIndex].withKey(sourceKey)
        return result
    }

    private static func validateNewBinding(bindings: [ShortcutBindingV1], binding: ShortcutBindingV1) throws {
        guard binding.executionRoute == .keyboardLocal else {
            throw ShortcutRegistryMutationError.hostHandoffUnavailable
        }
        guard !bindings.contains(where: { $0.id == binding.id }) else {
            throw ShortcutRegistryMutationError.bindingIDAlreadyExists
        }
    }
}

private extension ShortcutBindingV1 {
    func withKey(_ key: ShortcutKeyCode) -> ShortcutBindingV1 {
        ShortcutBindingV1(
            id: id,
            userID: userID,
            deviceID: deviceID,
            skillID: skillID,
            versionID: versionID,
            skillVersion: skillVersion,
            skillDigest: skillDigest,
            keyCode: key,
            presentation: ShortcutPresentation(
                iconKind: presentation.iconKind,
                iconValue: presentation.iconValue,
                shortLabel: presentation.shortLabel,
                accessibilityLabel: "\(key.displayLabel)、\(presentation.shortLabel)",
                accessibilityHint: presentation.accessibilityHint,
                tintToken: presentation.tintToken
            ),
            enabled: enabled,
            executionRoute: executionRoute,
            requiredConnectionIDs: requiredConnectionIDs,
            createdAt: createdAt,
            updatedAt: Date(),
            activationGesture: activationGesture,
            schemaVersion: schemaVersion
        )
    }
}
