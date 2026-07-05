import Foundation

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
