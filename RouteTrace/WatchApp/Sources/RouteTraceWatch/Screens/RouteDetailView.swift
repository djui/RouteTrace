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
                        .frame(height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    sectionHeader("Route")
                    detailRow("Distance", RouteFormatting.distance(route.distanceMeters))
                    detailRow("Elevation", RouteFormatting.elevation(route.elevationGainMeters))
                    detailRow("Offline Map", offlineLabel)

                    sectionHeader("Activity")
                    Picker("Type", selection: $selectedActivityKind) {
                        ForEach(ActivityKind.allCases) { kind in
                            Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    sectionHeader("Manage")
                    if route.offlineStatus != .missing {
                        Button(role: .destructive) {
                            showDeleteMapConfirm = true
                        } label: {
                            Text("Delete Offline Map")
                                .frame(maxWidth: .infinity)
                        }
                        .routeGlassButton(tint: .red)
                    }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Text("Delete Route")
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
            activeViewModel.beginGPSWarmup(
                preferences: preferences,
                activityKind: selectedActivityKind
            )
        }
        .onDisappear {
            activeViewModel.endGPSWarmup()
        }
        .onChange(of: selectedActivityKind) { _, kind in
            activeViewModel.setWarmupActivityKind(kind)
        }
        .confirmationDialog("Delete this route?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
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
        case .ready: "Ready"
        case .partial: "Partial"
        case .missing: "Not available"
        }
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.top, 4)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func startRoute() {
        isStarting = true
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
