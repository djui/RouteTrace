import Foundation

/// `type` values of messages, user infos and file transfers exchanged between iPhone and Watch.
public enum WatchMessageType {
    /// iPhone → Watch file: a `.routepack` archive.
    public static let routePackage = "routePackage"
    /// iPhone → Watch user info: the route was deleted on iPhone.
    public static let routeDeleted = "routeDeleted"
    /// iPhone → Watch user info: start navigating a route now (Siri or Shortcuts on iPhone).
    public static let startRoute = "startRoute"
    /// iPhone ↔ Watch user info: the routes were reordered; the newer order wins.
    public static let routeOrder = "routeOrder"
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
    public static let unitSystem = "unitSystem"
}

public struct SettingsSyncPayload: Sendable, Equatable {
    public let batteryMode: BatteryMode
    public let unitSystem: UnitSystem

    public init(batteryMode: BatteryMode, unitSystem: UnitSystem) {
        self.batteryMode = batteryMode
        self.unitSystem = unitSystem
    }

    public var dictionaryRepresentation: [String: Any] {
        [
            SettingsSyncKeys.type: SettingsSyncKeys.settingsSync,
            SettingsSyncKeys.batteryMode: batteryMode.rawValue,
            SettingsSyncKeys.unitSystem: unitSystem.rawValue
        ]
    }

    public init?(dictionary: [String: Any]) {
        guard dictionary[SettingsSyncKeys.type] as? String == SettingsSyncKeys.settingsSync,
              let rawValue = dictionary[SettingsSyncKeys.batteryMode] as? String,
              let batteryMode = BatteryMode(rawValue: rawValue) else {
            return nil
        }
        self.batteryMode = batteryMode
        // Payloads from app versions without a unit setting follow the region.
        self.unitSystem = (dictionary[SettingsSyncKeys.unitSystem] as? String).flatMap(UnitSystem.init(rawValue:)) ?? .automatic
    }
}
