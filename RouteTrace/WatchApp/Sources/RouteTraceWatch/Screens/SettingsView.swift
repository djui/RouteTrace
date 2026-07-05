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

    var runningSpeedDisplay: SpeedDisplayMode {
        didSet { UserDefaults.standard.set(runningSpeedDisplay.rawValue, forKey: Keys.runningSpeedDisplay) }
    }

    var cyclingSpeedDisplay: SpeedDisplayMode {
        didSet { UserDefaults.standard.set(cyclingSpeedDisplay.rawValue, forKey: Keys.cyclingSpeedDisplay) }
    }

    var isLowPowerModeEnabled: Bool {
        LowPowerModeStatus.isEnabled
    }

    func speedDisplayMode(for activityKind: ActivityKind) -> SpeedDisplayMode {
        switch activityKind.speedCategory {
        case .running: runningSpeedDisplay
        case .cycling: cyclingSpeedDisplay
        }
    }

    func applySyncedBatteryMode(_ mode: BatteryMode) {
        guard batteryMode != mode else { return }
        batteryMode = mode
    }

    private enum Keys {
        static let batteryMode = "watch.batteryMode"
        static let mapDisplayMode = "watch.mapDisplayMode"
        static let mapOrientation = "watch.mapOrientation"
        static let mapFollowMode = "watch.mapFollowMode"
        static let useHealthKitWorkouts = "watch.useHealthKitWorkouts"
        static let navigationNotificationsEnabled = "watch.navigationNotificationsEnabled"
        static let runningSpeedDisplay = "watch.runningSpeedDisplay"
        static let cyclingSpeedDisplay = "watch.cyclingSpeedDisplay"
        static let ultraSaverHealthKitPromptShown = "watch.ultraSaverHealthKitPromptShown"
    }

    static var shouldPromptUltraSaverHealthKit: Bool {
        !UserDefaults.standard.bool(forKey: Keys.ultraSaverHealthKitPromptShown)
    }

    static func markUltraSaverHealthKitPromptShown() {
        UserDefaults.standard.set(true, forKey: Keys.ultraSaverHealthKitPromptShown)
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
        runningSpeedDisplay = SpeedDisplayMode(
            rawValue: UserDefaults.standard.string(forKey: Keys.runningSpeedDisplay) ?? ""
        ) ?? .pace
        cyclingSpeedDisplay = SpeedDisplayMode(
            rawValue: UserDefaults.standard.string(forKey: Keys.cyclingSpeedDisplay) ?? ""
        ) ?? .speed
    }
}

struct SettingsView: View {
    @Environment(WatchPreferences.self) private var preferences

    @State private var showUltraSaverHealthKitPrompt = false

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            if preferences.isLowPowerModeEnabled {
                Section {
                    Label("Low Power Mode is on. Battery settings are elevated automatically.", systemImage: "battery.25")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Mode", selection: $preferences.batteryMode) {
                    ForEach(BatteryMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .onChange(of: preferences.batteryMode) { _, mode in
                    handleBatteryModeChange(mode)
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
                Text(mapSectionFooter)
            }

            Section {
                Toggle("Record HealthKit Workout", isOn: $preferences.useHealthKitWorkouts)
            } header: {
                Text("Workout")
            } footer: {
                Text("Turn off to navigate without heart rate or workout session overhead.")
            }

            Section {
                Toggle("Navigation Alerts", isOn: $preferences.navigationNotificationsEnabled)
            } header: {
                Text("Notifications")
            }

            Section {
                Picker("Running", selection: $preferences.runningSpeedDisplay) {
                    ForEach(SpeedDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Picker("Cycling", selection: $preferences.cyclingSpeedDisplay) {
                    ForEach(SpeedDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            } header: {
                Text("Speed")
            }
        }
        .navigationTitle("Settings")
        .alert("Save more battery?", isPresented: $showUltraSaverHealthKitPrompt) {
            Button("Turn Off Workout Recording") {
                preferences.useHealthKitWorkouts = false
                WatchPreferences.markUltraSaverHealthKitPromptShown()
            }
            Button("Keep Recording", role: .cancel) {
                WatchPreferences.markUltraSaverHealthKitPromptShown()
            }
        } message: {
            Text("Ultra Saver works best without HealthKit workout recording.")
        }
    }

    private var mapSectionFooter: String {
        var parts = [preferences.mapDisplayMode.detailDescription]
        if let hint = preferences.batteryMode.mapSettingsConflictHint,
           preferences.mapDisplayMode == .onlineNative {
            parts.append(hint)
        }
        return parts.joined(separator: " ")
    }

    private func handleBatteryModeChange(_ mode: BatteryMode) {
        if mode == .ultraSaver,
           preferences.useHealthKitWorkouts,
           WatchPreferences.shouldPromptUltraSaverHealthKit {
            showUltraSaverHealthKitPrompt = true
        }

        if let suggested = BatteryModePolicy(mode: mode).suggestedMapDisplayMode,
           preferences.mapDisplayMode != suggested {
            preferences.mapDisplayMode = suggested
        }
    }
}
