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
                            Label("Delete Offline Map", systemImage: "map")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Route", systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
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
        Button {
            startRoute()
        } label: {
            Text(isStarting ? "Starting…" : "Start")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .disabled(isStarting)
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
