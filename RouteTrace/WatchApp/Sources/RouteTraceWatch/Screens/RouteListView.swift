import RouteTraceShared
import SwiftUI

struct RouteListView: View {
    @Environment(WatchRouteStore.self) private var routeStore
    @Environment(WatchConnectivityManager.self) private var connectivity
    @Environment(WatchPreferences.self) private var preferences
    @State private var activeViewModel = ActiveRouteViewModel()
    @State private var showingSettings = false
    @State private var showActiveRoute = false
    @State private var didAttemptRestore = false
    @State private var routePendingDelete: RoutePackage?

    var body: some View {
        NavigationStack {
            Group {
                if routeStore.isLoading && routeStore.routes.isEmpty {
                    ProgressView("Loading routes…")
                } else if routeStore.routes.isEmpty {
                    ContentUnavailableView(
                        "No Routes",
                        systemImage: "map",
                        description: Text("Transfer a route from your iPhone to get started.")
                    )
                } else {
                    List {
                        if activeViewModel.isActive && !activeViewModel.isShowingSummary {
                            Section {
                                activeActivityBanner
                            }
                        }

                        Section {
                            ForEach(routeStore.routes) { route in
                                if activeViewModel.isActive {
                                    RouteRowView(route: route)
                                        .foregroundStyle(.secondary)
                                } else {
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
                    }
                }
            }
            .navigationTitle("Routes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .disabled(activeViewModel.isActive && !activeViewModel.isShowingSummary)
                }
            }
            .navigationDestination(for: UUID.self) { routeID in
                if let route = routeStore.route(with: routeID) {
                    RouteDetailView(route: route, activeViewModel: activeViewModel)
                }
            }
            .fullScreenCover(isPresented: $showActiveRoute) {
                ActiveRouteContainerView(viewModel: activeViewModel)
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
            .onChange(of: activeViewModel.isActive) { _, isActive in
                showActiveRoute = isActive
            }
            .onChange(of: activeViewModel.isShowingSummary) { _, showing in
                showActiveRoute = showing || activeViewModel.isActive
            }
            .onReceive(NotificationCenter.default.publisher(for: RouteTraceIntentNotifications.pauseResumeActivity)) { _ in
                activeViewModel.togglePauseResume(preferences: preferences)
            }
            .onReceive(NotificationCenter.default.publisher(for: RouteTraceIntentNotifications.startLastRoute)) { _ in
                Task {
                    await startLastRouteIfNeeded()
                }
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .navigationDestination(isPresented: $showingSettings) {
                SettingsView()
            }
            .refreshable {
                await routeStore.reload()
            }
            .task {
                guard !didAttemptRestore else { return }
                didAttemptRestore = true
                await routeStore.reload()
                if await activeViewModel.restoreIfNeeded(from: routeStore, preferences: preferences) {
                    showActiveRoute = true
                }
            }
        }
    }

    private var activeActivityBanner: some View {
        Button {
            showActiveRoute = true
        } label: {
            HStack {
                Image(systemName: "figure.run.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Activity in progress")
                        .font(.headline)
                    Text(activeViewModel.routePackage?.name ?? "Route")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.green.opacity(0.15))
    }

    private func startLastRouteIfNeeded() async {
        guard !activeViewModel.isActive, let route = routeStore.lastSelectedRoute else { return }
        await activeViewModel.start(
            route: route,
            activityKind: route.activityHint,
            preferences: preferences
        )
        showActiveRoute = true
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "routetrace", url.host == "active" else { return }
        if activeViewModel.isActive {
            showActiveRoute = true
        }
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
