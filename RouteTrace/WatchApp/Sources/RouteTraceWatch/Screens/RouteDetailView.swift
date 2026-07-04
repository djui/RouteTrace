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

    init(route: RoutePackage, activeViewModel: ActiveRouteViewModel) {
        self.route = route
        self.activeViewModel = activeViewModel
        _selectedActivityKind = State(initialValue: route.activityHint)
    }

    var body: some View {
        Form {
            Section {
                RoutePreviewMap(route: route)
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            Section("Route") {
                LabeledContent("Distance", value: RouteFormatting.distance(route.distanceMeters))
                LabeledContent("Elevation", value: RouteFormatting.elevation(route.elevationGainMeters))
                LabeledContent("Offline Map", value: offlineLabel)
            }

            Section("Activity") {
                Picker("Type", selection: $selectedActivityKind) {
                    ForEach(ActivityKind.allCases) { kind in
                        Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section("Manage") {
                if route.offlineStatus != .missing {
                    Button(role: .destructive) {
                        showDeleteMapConfirm = true
                    } label: {
                        Label("Delete Offline Map", systemImage: "map")
                    }
                }

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Route", systemImage: "trash")
                }
            }
        }
        .listSectionSpacing(8)
        .padding(.bottom, 44)
        .overlay(alignment: .bottom) {
            startRouteControl
                .padding(.horizontal, 16)
                .padding(.bottom, RouteAppearance.watchEdgeInset)
                .ignoresSafeArea(edges: .bottom)
        }
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
            Label(isStarting ? "Starting…" : "Start", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .controlSize(.large)
        .disabled(isStarting)
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
