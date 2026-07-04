import RouteTraceShared
import SwiftUI

@MainActor
@Observable
final class WatchPreferences {
    static let shared = WatchPreferences()

    var batteryMode: BatteryMode {
        didSet { UserDefaults.standard.set(batteryMode.rawValue, forKey: Keys.batteryMode) }
    }

    var mapDisplayMode: MapDisplayMode {
        didSet { UserDefaults.standard.set(mapDisplayMode.rawValue, forKey: Keys.mapDisplayMode) }
    }

    var mapOrientation: MapOrientationMode {
        didSet { UserDefaults.standard.set(mapOrientation.rawValue, forKey: Keys.mapOrientation) }
    }

    var mapFollowMode: Bool {
        didSet { UserDefaults.standard.set(mapFollowMode, forKey: Keys.mapFollowMode) }
    }

    var useHealthKitWorkouts: Bool {
        didSet { UserDefaults.standard.set(useHealthKitWorkouts, forKey: Keys.useHealthKitWorkouts) }
    }

    var navigationNotificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(navigationNotificationsEnabled, forKey: Keys.navigationNotificationsEnabled) }
    }

    private enum Keys {
        static let batteryMode = "watch.batteryMode"
        static let mapDisplayMode = "watch.mapDisplayMode"
        static let mapOrientation = "watch.mapOrientation"
        static let mapFollowMode = "watch.mapFollowMode"
        static let useHealthKitWorkouts = "watch.useHealthKitWorkouts"
        static let navigationNotificationsEnabled = "watch.navigationNotificationsEnabled"
    }

    private init() {
        batteryMode = BatteryMode(rawValue: UserDefaults.standard.string(forKey: Keys.batteryMode) ?? "") ?? .normal
        mapDisplayMode = MapDisplayMode(rawValue: UserDefaults.standard.string(forKey: Keys.mapDisplayMode) ?? "") ?? .onlineNative
        mapOrientation = MapOrientationMode(rawValue: UserDefaults.standard.string(forKey: Keys.mapOrientation) ?? "") ?? .northUp
        if UserDefaults.standard.object(forKey: Keys.mapFollowMode) == nil {
            mapFollowMode = true
        } else {
            mapFollowMode = UserDefaults.standard.bool(forKey: Keys.mapFollowMode)
        }
        if UserDefaults.standard.object(forKey: Keys.useHealthKitWorkouts) == nil {
            useHealthKitWorkouts = true
        } else {
            useHealthKitWorkouts = UserDefaults.standard.bool(forKey: Keys.useHealthKitWorkouts)
        }
        if UserDefaults.standard.object(forKey: Keys.navigationNotificationsEnabled) == nil {
            navigationNotificationsEnabled = true
        } else {
            navigationNotificationsEnabled = UserDefaults.standard.bool(forKey: Keys.navigationNotificationsEnabled)
        }
    }
}

struct SettingsView: View {
    @Environment(WatchPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            Section {
                Picker("Mode", selection: $preferences.batteryMode) {
                    ForEach(BatteryMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            } header: {
                Text("Battery")
            } footer: {
                Text(preferences.batteryMode.detailDescription)
            }

            Section {
                Picker("Display", selection: $preferences.mapDisplayMode) {
                    ForEach(MapDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Picker("Orientation", selection: $preferences.mapOrientation) {
                    ForEach(MapOrientationMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Toggle("Follow Location", isOn: $preferences.mapFollowMode)
            } header: {
                Text("Map")
            } footer: {
                Text(preferences.mapDisplayMode.detailDescription)
            }

            Section {
                Toggle("Navigation Alerts", isOn: $preferences.navigationNotificationsEnabled)
            } header: {
                Text("Notifications")
            }
        }
        .navigationTitle("Settings")
    }
}
