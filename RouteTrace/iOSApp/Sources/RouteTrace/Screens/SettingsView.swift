import RouteTraceShared
import SwiftData
import SwiftUI
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var routeStore: RouteStore
    #if canImport(WatchConnectivity)
    @EnvironmentObject private var connectivityManager: PhoneConnectivityManager
    #endif

    @State private var settings: AppSettingsEntity?

    var body: some View {
        NavigationStack {
            Form {
                if let settings {
                    Section {
                        Picker("Mode", selection: batteryModeBinding(for: settings)) {
                            ForEach(BatteryMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                    } header: {
                        Text("Battery")
                    } footer: {
                        Text(settings.batteryMode.detailDescription)
                    }

                    Section {
                        Picker("Default Activity", selection: defaultActivityBinding(for: settings)) {
                            ForEach(ActivityKind.allCases) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }
                        Toggle("Build Offline Packs by Default", isOn: offlinePackBinding(for: settings))
                    } header: {
                        Text("Routes")
                    } footer: {
                        Text(settingsFooter)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                loadSettingsIfNeeded()
            }
        }
    }

    private var settingsFooter: String {
        #if canImport(WatchConnectivity)
        "Battery mode syncs to your Apple Watch when connected."
        #else
        "Battery mode is used as the default for new activities."
        #endif
    }

    private func loadSettingsIfNeeded() {
        guard settings == nil else { return }
        settings = try? routeStore.loadSettings()
    }

    private func batteryModeBinding(for settings: AppSettingsEntity) -> Binding<BatteryMode> {
        Binding(
            get: { settings.batteryMode },
            set: { newValue in
                settings.batteryMode = newValue
                saveSettings()
                syncBatteryModeToWatch(newValue)
            }
        )
    }

    private func syncBatteryModeToWatch(_ mode: BatteryMode) {
        #if canImport(WatchConnectivity)
        connectivityManager.syncSettingsToWatch(batteryMode: mode)
        #endif
    }

    private func defaultActivityBinding(for settings: AppSettingsEntity) -> Binding<ActivityKind> {
        Binding(
            get: { settings.defaultActivityKind },
            set: { newValue in
                settings.defaultActivityKind = newValue
                saveSettings()
            }
        )
    }

    private func offlinePackBinding(for settings: AppSettingsEntity) -> Binding<Bool> {
        Binding(
            get: { settings.buildOfflinePacksByDefault },
            set: { newValue in
                settings.buildOfflinePacksByDefault = newValue
                saveSettings()
            }
        )
    }

    private func saveSettings() {
        try? routeStore.saveSettings()
    }
}
