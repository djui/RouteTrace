import SwiftUI
import SwiftData
import RouteTraceShared

struct RouteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var routeStore: RouteStore
    #if canImport(WatchConnectivity)
    @EnvironmentObject private var connectivityManager: PhoneConnectivityManager
    #endif

    @Bindable var route: RouteEntity

    @State private var routePackage: RoutePackage?
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var isMapFullscreenPresented = false
    @State private var showRenameAlert = false
    @State private var editedRouteName = ""
    @State private var showDeleteConfirmation = false
    @State private var showDeleteOfflineMapConfirmation = false

    /// Reload the package whenever something that changes it changes (also via iCloud).
    private var packageRevision: String {
        "\(route.name)|\(route.activityHintRaw)|\(route.simplifiedPointCount)|\(route.elevationGainMeters ?? -1)|\(route.elevationLossMeters ?? -1)|\(route.offlineTileCount)"
    }

    private var buildProgress: OfflinePackBuildProgress? {
        routeStore.offlineBuilds[route.id]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroMap
                summaryCard
                elevationCard
                #if canImport(WatchConnectivity)
                watchCard
                #endif
                offlineMapCard
                if let warning = routePackage?.navigationWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .card()
                }
                detailsCard
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        .fullScreenCover(isPresented: $isMapFullscreenPresented) {
            if let routePackage {
                RouteMapFullscreenView(
                    title: route.name,
                    subtitle: "\(RouteFormatting.distance(route.distanceMeters)) · \(RouteFormatting.elevation(route.elevationGainMeters)) ascent",
                    routePoints: routePackage.route,
                    trackPoints: []
                )
            }
        }
        .alert("Couldn’t Complete Action", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Rename Route", isPresented: $showRenameAlert) {
            TextField("Route Name", text: $editedRouteName)
                .textInputAutocapitalization(.words)
            Button("Save") { rename() }
                .disabled(editedRouteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(route.name)”?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Route", role: .destructive) { deleteRoute() }
        } message: {
            Text("The route and its offline map are removed from this iPhone and your Apple Watch. Recorded activities are kept.")
        }
        .confirmationDialog("Delete Offline Map?", isPresented: $showDeleteOfflineMapConfirmation, titleVisibility: .visible) {
            Button("Delete Offline Map", role: .destructive) { deleteOfflineMap() }
        } message: {
            Text("The route stays. Only the downloaded map tiles are removed.")
        }
        .task(id: packageRevision) {
            routePackage = try? routeStore.loadRoutePackage(for: route)
        }
        #if canImport(WatchConnectivity)
        .onAppear {
            connectivityManager.refreshSessionState()
        }
        #endif
    }

    // MARK: - Sections

    private var heroMap: some View {
        Button {
            isMapFullscreenPresented = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if let routePackage {
                    RouteMapPreview(routePoints: routePackage.route)
                } else {
                    Rectangle().fill(.quaternary)
                        .overlay { ProgressView() }
                }

                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .padding(12)
            }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: RouteDesign.cardCornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: RouteDesign.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show route map")
        .accessibilityHint("Opens the map full screen")
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                StatusChip(
                    title: route.activityHint.displayName,
                    systemImage: route.activityHint.systemImage,
                    tint: route.activityHint.tint
                )
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Text(route.importedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                HeadlineStat(title: "Distance", value: RouteFormatting.distance(route.distanceMeters))
                HeadlineStat(title: "Ascent", value: RouteFormatting.elevation(route.elevationGainMeters))
                HeadlineStat(title: "Descent", value: RouteFormatting.elevation(route.elevationLossMeters))
            }
        }
        .card()
    }

    @ViewBuilder
    private var elevationCard: some View {
        if let routePackage, routePackage.hasElevationData {
            let points = ProfilePoint.elevation(from: routePackage.route)
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Elevation", systemImage: "mountain.2.fill")
                ProfileChart(
                    points: points,
                    color: RouteDesign.routeColor,
                    seriesName: "Elevation",
                    unit: "m"
                )
            }
            .card()
        }
    }

    #if canImport(WatchConnectivity)
    private var watchCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Apple Watch", systemImage: "applewatch")

            if connectivityManager.canTransferToWatch {
                HStack(spacing: 12) {
                    Image(systemName: route.transferState.systemImage)
                        .font(.title3)
                        .foregroundStyle(route.transferState.tint)
                        .symbolEffect(.pulse, isActive: route.transferState == .transferring || route.transferState == .queued)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(route.transferState.displayName)
                            .font(.subheadline.weight(.semibold))
                        Text(watchStatusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    if route.transferState.canSend {
                        Button(route.transferState == .installed ? "Resend" : "Send") {
                            sendToWatch()
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                }
            } else {
                Label(connectivityManager.statusSummary, systemImage: "applewatch.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var watchStatusDetail: String {
        switch route.transferState {
        case .installed: "Start it from RouteTrace on your watch."
        case .queued, .transferring: "Delivered in the background, even if the watch is asleep."
        case .failed: "The last transfer didn’t complete."
        case .notSent: "Send it to navigate from your wrist."
        case .removedFromWatch: "You removed it on your watch."
        }
    }
    #endif

    private var offlineMapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Offline Map", systemImage: "map")

            if let buildProgress {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: buildProgress.fractionComplete)
                        .tint(.blue)
                    HStack {
                        Text(buildProgress.totalTiles > 0 ? buildProgress.statusText : "Preparing…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Spacer()
                        Button("Cancel", role: .cancel) {
                            routeStore.cancelOfflinePackBuild(for: route.id)
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            } else if route.offlineStatus == .missing {
                Text("Download map tiles along the route so the map on your watch works without a connection.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    routeStore.startOfflinePackBuild(for: route)
                } label: {
                    Label("Download Offline Map", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(isBusy)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: route.offlineStatus == .ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(route.offlineStatus == .ready ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(route.offlineStatus == .ready ? "Ready" : "Partial")
                            .font(.subheadline.weight(.semibold))
                        Text("\(route.offlineTileCount) tiles · \(ByteCountFormatter.string(fromByteCount: route.offlinePackSizeBytes, countStyle: .file))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer()
                    Menu {
                        Button {
                            routeStore.startOfflinePackBuild(for: route)
                        } label: {
                            Label("Rebuild", systemImage: "arrow.clockwise")
                        }
                        Button(role: .destructive) {
                            showDeleteOfflineMapConfirmation = true
                        } label: {
                            Label("Delete Offline Map", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .disabled(isBusy)
                    .accessibilityLabel("Offline Map Options")
                }
            }
        }
        .card()
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Details", systemImage: "info.circle")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                StatCell(
                    title: "Turn Cues",
                    value: routePackage.map { "\(max(0, $0.cues.count - 2))" } ?? "—",
                    systemImage: "arrow.triangle.turn.up.right.diamond",
                    tint: .purple
                )
                StatCell(
                    title: "Track Points",
                    value: pointsValue,
                    systemImage: "point.3.connected.trianglepath.dotted",
                    tint: .teal
                )
                if let range = elevationRange {
                    StatCell(title: "Highest", value: RouteFormatting.elevation(range.max), systemImage: "arrow.up.to.line", tint: .orange)
                    StatCell(title: "Lowest", value: RouteFormatting.elevation(range.min), systemImage: "arrow.down.to.line", tint: .mint)
                }
            }
            Divider()
            LabeledContent("Source File", value: route.sourceFileName)
                .font(.subheadline)
            LabeledContent("Imported", value: route.importedAt.formatted(date: .long, time: .shortened))
                .font(.subheadline)
        }
        .card()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if let routePackage {
                ShareLink(
                    item: GPXDocument.route(routePackage.renamed(to: route.name)),
                    preview: SharePreview(route.name)
                ) {
                    Label("Share GPX", systemImage: "square.and.arrow.up")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                RouteActionMenuItems(
                    route: route,
                    isBusy: isBusy,
                    onActivityKindChange: { kind in
                        perform { try await routeStore.updateActivityHint(for: route, to: kind) }
                    },
                    onReverseDirection: {
                        perform { try await routeStore.reverseRoute(for: route) }
                    },
                    onSendToWatch: sendToWatchAction,
                    onRename: {
                        editedRouteName = route.name
                        showRenameAlert = true
                    },
                    showsShare: false,
                    onDelete: { showDeleteConfirmation = true }
                )
            } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
    }

    // MARK: - Derived values

    private var pointsValue: String {
        if route.originalPointCount > route.simplifiedPointCount {
            return "\(route.simplifiedPointCount) of \(route.originalPointCount)"
        }
        return "\(route.simplifiedPointCount)"
    }

    private var elevationRange: (min: Double, max: Double)? {
        let values = routePackage?.route.compactMap(\.elevationMeters) ?? []
        guard let min = values.min(), let max = values.max() else { return nil }
        return (min, max)
    }

    // MARK: - Actions

    #if canImport(WatchConnectivity)
    private var sendToWatchAction: (() -> Void)? {
        connectivityManager.canTransferToWatch ? { sendToWatch() } : nil
    }

    private func sendToWatch() {
        do {
            try connectivityManager.transferRouteToWatch(routeID: route.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    #else
    private var sendToWatchAction: (() -> Void)? { nil }
    #endif

    private func perform(_ action: @escaping () async throws -> Void) {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await action()
                routePackage = try? routeStore.loadRoutePackage(for: route)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func rename() {
        do {
            try routeStore.renameRoute(for: route, to: editedRouteName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteOfflineMap() {
        do {
            try routeStore.deleteOfflinePack(for: route)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteRoute() {
        do {
            try routeStore.deleteRoute(route)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
