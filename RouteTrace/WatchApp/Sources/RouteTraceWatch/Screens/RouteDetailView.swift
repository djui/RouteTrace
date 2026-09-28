import RouteTraceShared
import SwiftUI

struct RouteDetailView: View {
    let route: RoutePackage
    @Bindable var activeViewModel: ActiveRouteViewModel

    @Environment(WatchRouteStore.self) private var routeStore
    @Environment(WatchPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    @State private var selectedActivityKind: ActivityKind
    @State private var isStarting = false
    @State private var showDeleteConfirm = false
    @State private var showDeleteMapConfirm = false

    private static let contentHorizontalPadding: CGFloat = 16
    private static let floatingStartClearance: CGFloat = 72
    private static let browseWarmupDelaySeconds: UInt64 = 45

    init(route: RoutePackage, activeViewModel: ActiveRouteViewModel) {
        self.route = route
        self.activeViewModel = activeViewModel
        _selectedActivityKind = State(initialValue: route.activityHint)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    RoutePreviewMap(route: route)
                        .frame(height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Grid(alignment: .leading, horizontalSpacing: 12) {
                        GridRow {
                            stat("Distance", RouteFormatting.distance(route.distanceMeters))
                            stat("Ascent", RouteFormatting.elevation(route.elevationGainMeters))
                        }
                    }

                    Label(offlineLabel, systemImage: route.offlineStatus == .missing ? "wifi" : "map.fill")
                        .font(.caption)
                        .foregroundStyle(route.offlineStatus == .missing ? Color.secondary : Color.blue)

                    Picker(selection: $selectedActivityKind) {
                        ForEach(ActivityKind.allCases) { kind in
                            Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                        }
                    } label: {
                        Label("Activity", systemImage: selectedActivityKind.systemImage)
                    }
                    .pickerStyle(.navigationLink)

                    if route.offlineStatus != .missing {
                        Button(role: .destructive) {
                            showDeleteMapConfirm = true
                        } label: {
                            Label("Delete Offline Map", systemImage: "map")
                                .frame(maxWidth: .infinity)
                        }
                        .routeGlassButton(tint: .red)
                    }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Remove Route", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .routeGlassButton(tint: .red)
                }
                .padding(.horizontal, Self.contentHorizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, Self.floatingStartClearance)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            startRouteControl
                .padding(.horizontal, Self.contentHorizontalPadding)
                .padding(.bottom, RouteAppearance.watchFloatingButtonBottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            routeStore.lastSelectedRouteID = route.id
        }
        .onDisappear {
            activeViewModel.endGPSWarmup()
        }
        .task(id: route.id) {
            await scheduleBrowseWarmupIfNeeded()
        }
        .onChange(of: selectedActivityKind) { _, kind in
            activeViewModel.setWarmupActivityKind(kind)
        }
        .confirmationDialog("Remove this route?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task {
                    try? await routeStore.deleteRoute(id: route.id)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete offline map?", isPresented: $showDeleteMapConfirm, titleVisibility: .visible) {
            Button("Delete Map", role: .destructive) {
                Task {
                    try? await routeStore.deleteOfflinePack(id: route.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The route stays on your Watch; only downloaded map tiles are removed.")
        }
    }

    private var offlineLabel: String {
        switch route.offlineStatus {
        case .ready: "Offline map on watch"
        case .partial: "Partial offline map"
        case .missing: "Map needs a connection"
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var startRouteControl: some View {
        VStack(spacing: 6) {
            if let gpsLabel = gpsWarmupLabel {
                Label(gpsLabel, systemImage: gpsWarmupIcon)
                    .font(.caption2)
                    .foregroundStyle(gpsWarmupColor)
            }

            Button {
                startRoute()
            } label: {
                Text(isStarting ? "Starting…" : "Start")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .routeGlassButton(prominent: true, tint: .green)
            .disabled(isStarting)
        }
    }

    private var gpsWarmupLabel: String? {
        switch activeViewModel.gpsAcquisitionState {
        case .warmingUp:
            return "Acquiring GPS…"
        case .ready where !activeViewModel.isActive:
            return "GPS ready"
        default:
            return nil
        }
    }

    private var gpsWarmupIcon: String {
        switch activeViewModel.gpsAcquisitionState {
        case .ready:
            return "location.fill"
        default:
            return "location.slash"
        }
    }

    private var gpsWarmupColor: Color {
        switch activeViewModel.gpsAcquisitionState {
        case .ready:
            return .green
        default:
            return .orange
        }
    }

    private func scheduleBrowseWarmupIfNeeded() async {
        let policy = BatteryModePolicy.policy(userMode: preferences.batteryMode)
        guard policy.enablesBrowseWarmup else { return }

        try? await Task.sleep(nanoseconds: Self.browseWarmupDelaySeconds * 1_000_000_000)
        guard !Task.isCancelled, !activeViewModel.isActive else { return }

        activeViewModel.beginGPSWarmup(
            preferences: preferences,
            activityKind: selectedActivityKind,
            browseWarmup: true
        )
    }

    private func startRoute() {
        isStarting = true
        activeViewModel.beginImminentStartWarmup(
            preferences: preferences,
            activityKind: selectedActivityKind
        )
        Task {
            await activeViewModel.start(
                route: route,
                activityKind: selectedActivityKind,
                preferences: preferences
            )
            isStarting = false
        }
    }
}
