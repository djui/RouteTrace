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
                    ContentUnavailableView {
                        Label("No Routes", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                    } description: {
                        Text("Import a GPX file in RouteTrace on your iPhone. It appears here automatically.")
                    }
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
                "Remove this route?",
                isPresented: Binding(
                    get: { routePendingDelete != nil },
                    set: { if !$0 { routePendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
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
            } message: {
                Text("It stays on your iPhone and can be sent again from there.")
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

    /// Routes in the order set on iPhone or here, newest first until reordered.
    private var orderedRoutes: [RoutePackage] {
        RouteOrderStore.shared.sorted(routeStore.routes, id: \.id, importedAt: \.importedAt)
    }

    private var libraryList: some View {
        List {
            if !routeStore.routes.isEmpty {
                Section("Routes") {
                    reorderableRouteRows
                }
            }

            Section("Recent Activities") {
                if activityStore.activities.isEmpty {
                    Text("Finished routes appear here.")
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
        .modifier(RouteReorderContainer(move: moveRoutes))
    }

    private var routeRows: some DynamicViewContent {
        ForEach(orderedRoutes) { route in
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

    /// Dragging routes into a new order needs watchOS 27.
    @ViewBuilder
    private var reorderableRouteRows: some View {
        #if compiler(>=6.4)
        if #available(watchOS 27.0, *) {
            routeRows.reorderable()
        } else {
            routeRows
        }
        #else
        routeRows
        #endif
    }

    private func moveRoutes(_ sources: [UUID], before destination: UUID?) {
        let displayed = orderedRoutes.map(\.id)
        let current = RouteOrderStore.shared.order ?? RouteOrder(routeIDs: displayed)
        let updated = current.moving(sources, before: destination, displayed: displayed)
        RouteOrderStore.shared.update(updated)
        connectivity.sendRouteOrder(updated)
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

/// Lets the route list take drops from `reorderable()` rows on watchOS 27.
private struct RouteReorderContainer: ViewModifier {
    let move: (_ sources: [UUID], _ destination: UUID?) -> Void

    func body(content: Content) -> some View {
        #if compiler(>=6.4)
        if #available(watchOS 27.0, *) {
            content.reorderContainer(for: RoutePackage.self) { difference in
                let destination: UUID? = switch difference.destination.position {
                case .before(let routeID): routeID
                case .end: nil
                }
                move(difference.sources, destination)
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct RouteRowView: View {
    let route: RoutePackage

    var body: some View {
        HStack(spacing: 10) {
            RouteShapeThumbnail(route: route)
                .overlay(alignment: .bottomTrailing) {
                    if route.offlineStatus != .missing {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white, .blue)
                            .offset(x: 4, y: 4)
                            .accessibilityLabel("Offline map")
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(route.name)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(RouteFormatting.distance(route.distanceMeters))
                    if let gain = route.elevationGainMeters, gain >= 1 {
                        Text("↑\(RouteFormatting.elevation(gain))")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
}
