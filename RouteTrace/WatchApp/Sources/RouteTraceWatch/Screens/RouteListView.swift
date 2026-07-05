import RouteTraceShared
import SwiftUI

struct RouteListView: View {
    @Environment(WatchRouteStore.self) private var routeStore
    @Environment(WatchActivityStore.self) private var activityStore
    @Environment(WatchConnectivityManager.self) private var connectivity
    @Environment(WatchCloudRouteSyncService.self) private var cloudSync
    @Environment(WatchPreferences.self) private var preferences
    @State private var activeViewModel = ActiveRouteViewModel()
    @State private var showingSettings = false
    @State private var didAttemptRestore = false
    @State private var routePendingDelete: RoutePackage?
    @State private var activityPendingDelete: ActivityRecording?

    var body: some View {
        Group {
            if activeViewModel.isActive {
                ActiveRouteContainerView(viewModel: activeViewModel)
            } else {
                libraryNavigationStack
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: RouteTraceIntentNotifications.pauseResumeActivity)) { _ in
            activeViewModel.togglePauseResume(preferences: preferences)
        }
        .onReceive(NotificationCenter.default.publisher(for: RouteTraceIntentNotifications.toggleMapDirections)) { _ in
            // Handled in ActiveRouteContainerView when active.
        }
        .onChange(of: preferences.batteryMode) { _, _ in
            if activeViewModel.isActive {
                activeViewModel.applyBatterySettings(from: preferences)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            if activeViewModel.isActive {
                activeViewModel.applyBatterySettings(from: preferences)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: RouteTraceIntentNotifications.startLastRoute)) { _ in
            Task {
                await startLastRouteIfNeeded()
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .task {
            guard !didAttemptRestore else { return }
            didAttemptRestore = true
            await routeStore.reload()
            await activityStore.reload()
            _ = await activeViewModel.restoreIfNeeded(from: routeStore, preferences: preferences)
        }
    }

    private var libraryNavigationStack: some View {
        NavigationStack {
            Group {
                if isLoadingLibrary && routeStore.routes.isEmpty && activityStore.activities.isEmpty {
                    ProgressView(cloudSync.isSyncing ? "Syncing routes…" : "Loading…")
                } else if routeStore.routes.isEmpty && activityStore.activities.isEmpty {
                    ContentUnavailableView(
                        "No Routes",
                        systemImage: "map",
                        description: Text("Import a route on iPhone — it will appear here automatically via iCloud or Apple Watch transfer.")
                    )
                } else {
                    libraryList
                }
            }
            .navigationTitle("RouteTrace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let route = routeStore.route(with: id) {
                    RouteDetailView(route: route, activeViewModel: activeViewModel)
                } else if let activity = activityStore.activity(with: id) {
                    WatchActivityDetailView(activity: activity)
                }
            }
            .confirmationDialog(
                "Delete this route?",
                isPresented: Binding(
                    get: { routePendingDelete != nil },
                    set: { if !$0 { routePendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let route = routePendingDelete {
                        Task {
                            try? await routeStore.deleteRoute(id: route.id)
                            routePendingDelete = nil
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    routePendingDelete = nil
                }
            }
            .confirmationDialog(
                "Remove from Watch?",
                isPresented: Binding(
                    get: { activityPendingDelete != nil },
                    set: { if !$0 { activityPendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let activity = activityPendingDelete {
                        Task {
                            try? await activityStore.delete(id: activity.id)
                            activityPendingDelete = nil
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    activityPendingDelete = nil
                }
            } message: {
                Text("This only removes the activity from your Apple Watch. Your iPhone copy is not affected.")
            }
            .navigationDestination(isPresented: $showingSettings) {
                SettingsView()
            }
            .refreshable {
                await routeStore.reload()
                await activityStore.reload()
            }
        }
    }

    private var isLoadingLibrary: Bool {
        routeStore.isLoading || activityStore.isLoading || cloudSync.isSyncing
    }

    private var libraryList: some View {
        List {
            if !routeStore.routes.isEmpty {
                Section("Routes") {
                    ForEach(routeStore.routes) { route in
                        NavigationLink(value: route.id) {
                            RouteRowView(route: route)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                routePendingDelete = route
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section("Activities") {
                if activityStore.activities.isEmpty {
                    Text("No completed activities yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activityStore.activities) { activity in
                        NavigationLink(value: activity.id) {
                            WatchActivityRowView(activity: activity)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                activityPendingDelete = activity
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private func startLastRouteIfNeeded() async {
        guard !activeViewModel.isActive, let route = routeStore.lastSelectedRoute else { return }
        await activeViewModel.start(
            route: route,
            activityKind: route.activityHint,
            preferences: preferences
        )
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "routetrace", url.host == "active" else { return }
    }
}

private struct RouteRowView: View {
    let route: RoutePackage

    var body: some View {
        HStack(spacing: 10) {
            RouteShapeThumbnail(route: route)

            VStack(alignment: .leading, spacing: 4) {
                Text(route.name)
                    .font(.headline)
                HStack {
                    Label(RouteFormatting.distance(route.distanceMeters), systemImage: "ruler")
                    Spacer()
                    offlineBadge
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var offlineBadge: some View {
        switch route.offlineStatus {
        case .ready:
            Label("Offline", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(.green)
        case .partial:
            Label("Partial", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .missing:
            Label("Online only", systemImage: "wifi")
        }
    }
}
