import Foundation

/// `type` values of messages, user infos and file transfers exchanged between iPhone and Watch.
public enum WatchMessageType {
    /// iPhone → Watch file: a `.routepack` archive.
    public static let routePackage = "routePackage"
    /// iPhone → Watch user info: the route was deleted on iPhone.
    public static let routeDeleted = "routeDeleted"
    /// Watch → iPhone: a route archive was installed.
    public static let routeInstalled = "routeInstalled"
    /// Watch → iPhone: the user removed the route from the watch.
    public static let routeRemoved = "routeRemoved"
    /// Watch → iPhone file: a finished activity recording.
    public static let activityRecording = "activityRecording"
}

public enum SettingsSyncKeys {
    public static let type = "type"
    public static let settingsSync = "settingsSync"
    public static let batteryMode = "batteryMode"
}

public struct SettingsSyncPayload: Sendable, Equatable {
    public let batteryMode: BatteryMode

    public init(batteryMode: BatteryMode) {
        self.batteryMode = batteryMode
    }

    public var dictionaryRepresentation: [String: Any] {
        [
            SettingsSyncKeys.type: SettingsSyncKeys.settingsSync,
            SettingsSyncKeys.batteryMode: batteryMode.rawValue
        ]
    }

    public init?(dictionary: [String: Any]) {
        guard dictionary[SettingsSyncKeys.type] as? String == SettingsSyncKeys.settingsSync,
              let rawValue = dictionary[SettingsSyncKeys.batteryMode] as? String,
              let batteryMode = BatteryMode(rawValue: rawValue) else {
            return nil
        }
        self.batteryMode = batteryMode
    }
}
