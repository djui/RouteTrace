import SwiftUI
import SwiftData
import RouteTraceShared

struct RouteLibraryView: View {
    @EnvironmentObject private var routeStore: RouteStore
    @EnvironmentObject private var incomingGPX: IncomingGPXCoordinator
    #if canImport(WatchConnectivity)
    @EnvironmentObject private var connectivityManager: PhoneConnectivityManager
    #endif

    @Query(sort: \RouteEntity.importedAt, order: .reverse) private var routes: [RouteEntity]

    @State private var path = NavigationPath()
    @State private var searchText = ""
    @State private var isFileImporterPresented = false
    @State private var importItem: ImportItem?
    @State private var isLoadingImport = false
    @State private var isShowingSettings = false
    @State private var errorMessage: String?
    @State private var routePendingRename: RouteEntity?
    @State private var routePendingDelete: RouteEntity?
    @State private var editedRouteName = ""
    @State private var busyRouteIDs: Set<UUID> = []
    @State private var banner: BannerContent?

    /// Routes in the order set here or on the Watch, newest first until reordered.
    private var orderedRoutes: [RouteEntity] {
        RouteOrderStore.shared.sorted(routes, id: \.id, importedAt: \.importedAt)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredRoutes: [RouteEntity] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return orderedRoutes }
        return orderedRoutes.filter { $0.name.localizedStandardContains(query) }
    }

    private var showsWatchStatus: Bool {
        #if canImport(WatchConnectivity)
        connectivityManager.canTransferToWatch
        #else
        false
        #endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Routes")
                .toolbar { toolbarContent }
                .navigationDestination(for: UUID.self) { routeID in
                    if let route = routes.first(where: { $0.id == routeID }) {
                        RouteDetailView(route: route)
                    } else {
                        ContentUnavailableView("Route Deleted", systemImage: "trash")
                    }
                }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.gpx, .xml],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task { await prepareImport(from: url) }
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $importItem) { item in
            ImportRouteView(candidate: item.candidate) { entity in
                importItem = nil
                path.append(entity.id)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .alert("Couldn’t Complete Action", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Rename Route", isPresented: Binding(
            get: { routePendingRename != nil },
            set: { if !$0 { routePendingRename = nil } }
        )) {
            TextField("Route Name", text: $editedRouteName)
                .textInputAutocapitalization(.words)
            Button("Save") {
                if let route = routePendingRename {
                    rename(route, to: editedRouteName)
                }
            }
            .disabled(editedRouteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        .overlay {
            if isLoadingImport {
                ProgressView("Reading GPX…")
                    .padding(24)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .transientBanner($banner)
        .onChange(of: incomingGPX.pendingImport?.id) { _, _ in
            if let url = incomingGPX.pendingImport?.url {
                incomingGPX.clearPending()
                Task { await prepareImport(from: url) }
            }
        }
        .onChange(of: routeStore.offlineBuildFailure) { _, failure in
            if let failure {
                errorMessage = "Offline map for \(failure.routeName): \(failure.message)"
                routeStore.offlineBuildFailure = nil
            }
        }
        #if canImport(WatchConnectivity)
        .onChange(of: connectivityManager.lastEvent) { _, event in
            guard let event else { return }
            banner = BannerContent(
                message: event.message,
                systemImage: event.kind == .failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                tint: event.kind == .failed ? .orange : .green
            )
        }
        .onChange(of: routes.map(\.name)) { _, _ in
            // Siri learns route names from the App Shortcut phrases.
            RouteTraceShortcuts.updateAppShortcutParameters()
        }
        #endif
        .task {
            #if canImport(WatchConnectivity)
            RouteTraceShortcuts.updateAppShortcutParameters()
            #endif
            if let url = incomingGPX.pendingImport?.url {
                incomingGPX.clearPending()
                await prepareImport(from: url)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if routes.isEmpty {
            ContentUnavailableView {
                Label("No Routes Yet", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
            } description: {
                Text("Import a GPX file from Komoot, Strava, Garmin or any route planner. RouteTrace sends it to your Apple Watch for turn-by-turn navigation.")
            } actions: {
                Button {
                    isFileImporterPresented = true
                } label: {
                    Label("Import GPX File", systemImage: "square.and.arrow.down")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        } else {
            List {
                ForEach(filteredRoutes) { route in
                    NavigationLink(value: route.id) {
                        RouteRow(
                            route: route,
                            thumbnail: routeStore.thumbnailPoints(for: route),
                            buildProgress: routeStore.offlineBuilds[route.id],
                            isBusy: busyRouteIDs.contains(route.id),
                            showsWatchStatus: showsWatchStatus
                        )
                    }
                    .contextMenu {
                        actionMenu(for: route)
                    } preview: {
                        RoutePreviewCard(route: route, thumbnail: routeStore.thumbnailPoints(for: route))
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            routePendingDelete = route
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                    // Attached per row so the popover points at the route being deleted.
                    .confirmationDialog(
                        "Delete “\(route.name)”?",
                        isPresented: deleteConfirmationBinding(for: route),
                        titleVisibility: .visible
                    ) {
                        Button("Delete Route", role: .destructive) {
                            delete(route)
                        }
                    } message: {
                        Text("The route and its offline map are removed from this iPhone and your Apple Watch. Recorded activities are kept.")
                    }
                    #if canImport(WatchConnectivity)
                    .swipeActions(edge: .leading) {
                        if showsWatchStatus {
                            Button {
                                sendToWatch(route)
                            } label: {
                                Label("Send to Watch", systemImage: "applewatch.and.arrow.forward")
                            }
                            .tint(.green)
                        }
                    }
                    #endif
                }
                .onMove(perform: moveAction)
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Search Routes")
            .overlay {
                if filteredRoutes.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isShowingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                isFileImporterPresented = true
            } label: {
                Label("Import GPX", systemImage: "plus")
            }
            .disabled(isLoadingImport)
        }
        if routes.count > 1 && !isSearching {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }

    @ViewBuilder
    private func actionMenu(for route: RouteEntity) -> some View {
        #if canImport(WatchConnectivity)
        let sendAction: (() -> Void)? = showsWatchStatus ? { sendToWatch(route) } : nil
        #else
        let sendAction: (() -> Void)? = nil
        #endif
        RouteActionMenuItems(
            route: route,
            isBusy: busyRouteIDs.contains(route.id),
            onActivityKindChange: { kind in
                perform(on: route) { try await routeStore.updateActivityHint(for: route, to: kind) }
            },
            onReverseDirection: {
                perform(on: route) { try await routeStore.reverseRoute(for: route) }
            },
            onSendToWatch: sendAction,
            onRename: {
                editedRouteName = route.name
                routePendingRename = route
            },
            onDelete: { routePendingDelete = route }
        )
    }

    // MARK: - Actions

    /// Moving within search results would be ambiguous, so reordering is off while searching.
    private var moveAction: ((IndexSet, Int) -> Void)? {
        guard !isSearching else { return nil }
        return { offsets, offset in moveRoutes(from: offsets, to: offset) }
    }

    private func moveRoutes(from offsets: IndexSet, to offset: Int) {
        let displayed = orderedRoutes.map(\.id)
        let current = RouteOrderStore.shared.order ?? RouteOrder(routeIDs: displayed)
        let updated = current.moving(
            offsets.map { displayed[$0] },
            before: RouteOrder.destination(forListOffset: offset, in: displayed),
            displayed: displayed
        )
        RouteOrderStore.shared.update(updated)
        #if canImport(WatchConnectivity)
        connectivityManager.sendRouteOrder(updated)
        #endif
    }

    private func prepareImport(from url: URL) async {
        isLoadingImport = true
        defer { isLoadingImport = false }
        do {
            let candidate = try await GPXImportCandidate.load(from: url)
            importItem = ImportItem(candidate: candidate)
        } catch {
            errorMessage = "“\(url.lastPathComponent)” couldn’t be imported. \(error.localizedDescription)"
        }
    }

    private func perform(on route: RouteEntity, _ action: @escaping () async throws -> Void) {
        let routeID = route.id
        busyRouteIDs.insert(routeID)
        Task {
            defer { busyRouteIDs.remove(routeID) }
            do {
                try await action()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func rename(_ route: RouteEntity, to name: String) {
        do {
            try routeStore.renameRoute(for: route, to: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ route: RouteEntity) {
        do {
            try routeStore.deleteRoute(route)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteConfirmationBinding(for route: RouteEntity) -> Binding<Bool> {
        Binding(
            get: { routePendingDelete?.id == route.id },
            set: { isPresented in
                if !isPresented, routePendingDelete?.id == route.id {
                    routePendingDelete = nil
                }
            }
        )
    }

    #if canImport(WatchConnectivity)
    private func sendToWatch(_ route: RouteEntity) {
        do {
            try connectivityManager.transferRouteToWatch(routeID: route.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    #endif
}

struct ImportItem: Identifiable {
    let id = UUID()
    let candidate: GPXImportCandidate
}

private struct RouteRow: View {
    let route: RouteEntity
    let thumbnail: [GeoCoordinate]
    let buildProgress: OfflinePackBuildProgress?
    let isBusy: Bool
    let showsWatchStatus: Bool

    var body: some View {
        HStack(spacing: 14) {
            RouteShapeThumbnail(coordinates: thumbnail, size: 62)

            VStack(alignment: .leading, spacing: 5) {
                Text(route.name)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    metric(RouteFormatting.distance(route.distanceMeters), systemImage: "arrow.left.and.right")
                    if let gain = route.elevationGainMeters, gain >= 1 {
                        metric(RouteFormatting.elevation(gain), systemImage: "arrow.up.right")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    StatusChip(
                        title: route.activityHint.displayName,
                        systemImage: route.activityHint.systemImage,
                        tint: route.activityHint.tint
                    )
                    if let buildProgress {
                        OfflineBuildChip(progress: buildProgress)
                    } else if route.offlineStatus != .missing {
                        StatusChip(
                            title: "Offline",
                            systemImage: route.offlineStatus.systemImage,
                            tint: route.offlineStatus.tint
                        )
                    }
                    if showsWatchStatus {
                        Image(systemName: route.transferState.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(route.transferState.tint)
                            .accessibilityLabel(route.transferState.displayName)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isBusy {
                ProgressView()
            }
        }
        .padding(.vertical, 4)
    }

    private func metric(_ value: String, systemImage: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .imageScale(.small)
            Text(value)
                .monospacedDigit()
        }
    }
}

private struct OfflineBuildChip: View {
    let progress: OfflinePackBuildProgress

    var body: some View {
        HStack(spacing: 5) {
            ProgressView(value: max(progress.fractionComplete, 0.02))
                .progressViewStyle(.circular)
                .controlSize(.mini)
            Text("Map \(Int(progress.fractionComplete * 100))%")
                .monospacedDigit()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.blue)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.blue.opacity(0.13), in: Capsule())
        .accessibilityLabel("Downloading offline map, \(Int(progress.fractionComplete * 100)) percent")
    }
}

/// Larger preview shown when long-pressing a route.
private struct RoutePreviewCard: View {
    let route: RouteEntity
    let thumbnail: [GeoCoordinate]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RouteShapeThumbnail(coordinates: thumbnail, size: 240)
            Text(route.name)
                .font(.headline)
            HStack(spacing: 16) {
                HeadlineStat(title: "Distance", value: RouteFormatting.distance(route.distanceMeters))
                HeadlineStat(title: "Ascent", value: RouteFormatting.elevation(route.elevationGainMeters))
            }
        }
        .padding(20)
        .frame(width: 280)
    }
}
