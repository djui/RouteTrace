import RouteTraceShared
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var routeStore: RouteStore
    #if canImport(WatchConnectivity)
    @EnvironmentObject private var connectivityManager: PhoneConnectivityManager
    #endif

    @Query private var routes: [RouteEntity]
    @Query private var activities: [ActivityEntity]

    @State private var settings: AppSettingsEntity?
    @State private var offlineMapsBytes: Int64?

    var body: some View {
        NavigationStack {
            Form {
                if let settings {
                    watchSection(settings)

                    Section {
                        Picker(selection: defaultActivityBinding(for: settings)) {
                            ForEach(ActivityKind.allCases) { kind in
                                Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                            }
                        } label: {
                            Label("Default Activity", systemImage: "figure.run")
                        }
                        Toggle(isOn: offlinePackBinding(for: settings)) {
                            Label("Download Offline Maps", systemImage: "map")
                        }
                    } header: {
                        Text("New Routes")
                    } footer: {
                        Text("Preselected when importing a GPX file. Offline maps are prepared in the background after import.")
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }

                Section("Storage") {
                    LabeledContent("Routes", value: "\(routes.count)")
                    LabeledContent("Activities", value: "\(activities.count)")
                    LabeledContent("Offline Maps") {
                        if let offlineMapsBytes {
                            Text(ByteCountFormatter.string(fromByteCount: offlineMapsBytes, countStyle: .file))
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.versionDescription)
                } footer: {
                    Text("Routes and activities sync through iCloud. Offline maps stay on the device that built them.")
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
                if settings == nil {
                    settings = try? routeStore.loadSettings()
                }
                offlineMapsBytes = await Self.offlineMapsSize()
            }
        }
    }

    @ViewBuilder
    private func watchSection(_ settings: AppSettingsEntity) -> some View {
        Section {
            #if canImport(WatchConnectivity)
            Label {
                Text(connectivityManager.statusSummary)
            } icon: {
                Image(systemName: connectivityManager.canTransferToWatch ? "applewatch" : "applewatch.slash")
                    .foregroundStyle(connectivityManager.canTransferToWatch ? .green : .secondary)
            }
            #endif

            Picker(selection: batteryModeBinding(for: settings)) {
                ForEach(BatteryMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            } label: {
                Label("Battery Mode", systemImage: "battery.75percent")
            }
        } header: {
            Text("Apple Watch")
        } footer: {
            Text(settings.batteryMode.detailDescription)
        }
    }

    private func batteryModeBinding(for settings: AppSettingsEntity) -> Binding<BatteryMode> {
        Binding(
            get: { settings.batteryMode },
            set: { newValue in
                settings.batteryMode = newValue
                try? routeStore.saveSettings()
                #if canImport(WatchConnectivity)
                connectivityManager.syncSettingsToWatch(batteryMode: newValue)
                #endif
            }
        )
    }

    private func defaultActivityBinding(for settings: AppSettingsEntity) -> Binding<ActivityKind> {
        Binding(
            get: { settings.defaultActivityKind },
            set: { newValue in
                settings.defaultActivityKind = newValue
                try? routeStore.saveSettings()
            }
        )
    }

    private func offlinePackBinding(for settings: AppSettingsEntity) -> Binding<Bool> {
        Binding(
            get: { settings.buildOfflinePacksByDefault },
            set: { newValue in
                settings.buildOfflinePacksByDefault = newValue
                try? routeStore.saveSettings()
            }
        )
    }

    private static func offlineMapsSize() async -> Int64 {
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            guard let enumerator = fileManager.enumerator(
                at: RouteTracePaths.routesRoot,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
            ) else { return 0 }

            var total: Int64 = 0
            while let url = enumerator.nextObject() as? URL {
                guard url.pathComponents.contains("tiles") else { continue }
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values?.isRegularFile == true {
                    total += Int64(values?.fileSize ?? 0)
                }
            }
            return total
        }.value
    }
}

extension Bundle {
    var versionDescription: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
