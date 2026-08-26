import Foundation

public struct FieldSecurityContext: Equatable, Sendable {
    public let isSecureTextEntry: Bool
    public let textContentType: String?
    public let keyboardType: String?

    public init(isSecureTextEntry: Bool = false, textContentType: String? = nil, keyboardType: String? = nil) {
        self.isSecureTextEntry = isSecureTextEntry
        self.textContentType = textContentType
        self.keyboardType = keyboardType
    }
}

public struct SensitiveFieldPolicy: Sendable {
    public init() {}

    public func lockReason(for field: FieldSecurityContext) -> LockReason? {
        if field.isSecureTextEntry { return .secureField }
        let sensitiveTypes: Set<String> = [
            "password", "newPassword", "oneTimeCode", "creditCardNumber",
            "creditCardSecurityCode", "creditCardExpirationDate", "creditCardExpirationMonth", "creditCardExpirationYear"
        ]
        if let type = field.textContentType, sensitiveTypes.contains(type) { return .secureField }
        if field.keyboardType == "asciiCapableNumberPad" && field.textContentType == "oneTimeCode" { return .secureField }
        let unsupportedKeyboardTypes: Set<String> = ["phonePad", "numberPad", "decimalPad", "asciiCapableNumberPad"]
        if let keyboardType = field.keyboardType, unsupportedKeyboardTypes.contains(keyboardType) { return .unsupportedField }
        return nil
    }

    public func allowsAI(for field: FieldSecurityContext) -> Bool { lockReason(for: field) == nil }
}
