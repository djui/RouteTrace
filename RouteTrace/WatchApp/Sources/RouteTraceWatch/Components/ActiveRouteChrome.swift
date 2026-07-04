import RouteTraceShared
import SwiftUI

enum RoutePage: Int, CaseIterable, Identifiable {
    case routeMap
    case followRoute
    case liveMap
    case altitude
    case metrics

    var id: Int { rawValue }

    var activeDotColor: Color {
        switch self {
        case .followRoute: .green
        case .routeMap, .liveMap, .altitude: .blue
        case .metrics: .white
        }
    }

    var supportsMapFocus: Bool {
        self == .routeMap || self == .liveMap
    }
}

enum ActiveInteractionMode: Equatable {
    case browse
    case mapFocus
}

@MainActor
@Observable
final class ActiveRouteUIState {
    var selectedPage: RoutePage = .routeMap
    var interactionMode: ActiveInteractionMode = .browse
    var mapSpan: Double = 0.012

    var isMapFocus: Bool { interactionMode == .mapFocus }

    func enterMapFocus() {
        guard selectedPage.supportsMapFocus else { return }
        interactionMode = .mapFocus
    }

    func exitMapFocus() {
        interactionMode = .browse
    }
}

struct ActiveRoutePageDots: View {
    let selectedPage: RoutePage

    var body: some View {
        HStack(spacing: 7) {
            ForEach(RoutePage.allCases) { page in
                Circle()
                    .fill(page == selectedPage ? page.activeDotColor : Color.white.opacity(0.3))
                    .frame(
                        width: page == selectedPage ? 6 : 5,
                        height: page == selectedPage ? 6 : 5
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .allowsHitTesting(false)
    }
}

struct ActiveRouteStatusBar: View {
    let activityKind: ActivityKind

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 4) {
                Image(systemName: activityKind.systemImage)
                    .foregroundStyle(.green)
                    .font(.caption2)
                Text(context.date, style: .time)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
    }
}

struct ActiveRouteChrome<Content: View>: View {
    @Bindable var uiState: ActiveRouteUIState
    @Bindable var viewModel: ActiveRouteViewModel

    @Environment(WatchPreferences.self) private var preferences

    let showFinishConfirm: Binding<Bool>
    @ViewBuilder let content: () -> Content

    @State private var showActivityActions = false

    var body: some View {
        ZStack {
            content()

            VStack(spacing: 0) {
                topBar
                Spacer()
                if uiState.isMapFocus {
                    mapFocusDoneBar
                }
                ActiveRoutePageDots(selectedPage: uiState.selectedPage)
                    .padding(.bottom, 6)
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)
        }
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showActivityActions) {
            activityActionsSheet
        }
    }

    private var activityActionsSheet: some View {
        NavigationStack {
            List {
                Button {
                    showActivityActions = false
                    viewModel.togglePauseResume(preferences: preferences)
                } label: {
                    Label(
                        viewModel.isPaused ? "Resume" : "Pause",
                        systemImage: viewModel.isPaused ? "play.fill" : "pause.fill"
                    )
                }

                Button {
                    showActivityActions = false
                    showFinishConfirm.wrappedValue = true
                } label: {
                    Label("Finish Activity", systemImage: "flag.checkered")
                }
            }
            .navigationTitle("Activity")
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            Button {
                showActivityActions = true
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            ActiveRouteStatusBar(activityKind: viewModel.activityKind)
                .padding(.top, 8)
                .padding(.trailing, 2)
        }
    }

    private var mapFocusDoneBar: some View {
        HStack {
            Spacer()
            Button("Done") {
                uiState.exitMapFocus()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.55), in: Capsule())
        }
        .padding(.bottom, 4)
    }
}

struct OfflineStatusPill: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "icloud.slash")
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.65), in: Capsule())
    }
}

struct RouteMetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        }
    }
}
