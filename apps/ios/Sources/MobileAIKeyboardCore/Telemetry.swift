import Foundation

public enum TelemetryEvent: String, Codable, Sendable {
    case keyboardOpened
    case commandOpened
    case captureReviewed
    case rewriteApplied
    case actionCancelled
    case secureFieldLocked
    case errorShown
}

public struct ContentFreeTelemetry: Codable, Equatable, Sendable {
    public let event: TelemetryEvent
    public let appVersion: String
    public let osMajorVersion: Int
    public let locale: String

    public init(event: TelemetryEvent, appVersion: String, osMajorVersion: Int, locale: String) {
        self.event = event
        self.appVersion = appVersion
        self.osMajorVersion = osMajorVersion
        self.locale = locale
    }
}

/// Only this allow-listed value type may be passed to a future analytics adapter.
public struct TelemetryRecorder: Sendable {
    public init() {}
    public func event(_ event: TelemetryEvent, appVersion: String, osMajorVersion: Int, locale: String) -> ContentFreeTelemetry {
        ContentFreeTelemetry(event: event, appVersion: appVersion, osMajorVersion: osMajorVersion, locale: locale)
    }
}
