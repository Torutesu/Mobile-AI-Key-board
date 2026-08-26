import Foundation

/// Platform-neutral layout contract used by the native extension and its tests.
public enum OrdinaryKeyboardLayout: Sendable {
    public static let letterRows: [String] = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    public static let bottomKeys: [String] = ["globe", "space", "return"]
    public static let utilityKeys: Set<String> = ["shift", "delete"]
}
