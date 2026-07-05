import MapKit
import RouteTraceShared
import SwiftUI

struct RouteOnlyMapView: View {
    @Bindable var viewModel: ActiveRouteViewModel
    @Bindable var uiState: ActiveRouteUIState

    @Environment(WatchPreferences.self) private var preferences
    @Environment(\.colorScheme) private var colorScheme

    @State private var recenterToken = 0

    private var isFocused: Bool {
        uiState.isMapFocus
    }

    private var isMapVisible: Bool {
        uiState.selectedPage == .liveMap || isFocused
    }

    private var batteryPolicy: BatteryModePolicy {
        BatteryModePolicy.policy(userMode: preferences.batteryMode)
    }

    var body: some View {
        AlwaysOnAware {
            GeometryReader { _ in
                Canvas { context, size in
                    drawRouteMap(context: &context, size: size)
                }
                .id(recenterToken)
                .background(RouteAppearance.offlineMapCanvas(for: colorScheme))
            }
        } dimmed: {
            ActiveRouteDimmedSummary(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: viewModel.displayCoordinate?.latitude) { _, _ in
            followLocationIfNeeded()
        }
        .onChange(of: viewModel.displayCoordinate?.longitude) { _, _ in
            followLocationIfNeeded()
        }
        .onChange(of: uiState.mapSpan) { _, _ in
            if !isFocused {
                recenterIfNeeded()
            }
        }
        .onAppear {
            if !isFocused {
                recenterIfNeeded()
            }
        }
    }

    private func drawRouteMap(context: inout GraphicsContext, size: CGSize) {
        guard let route = viewModel.routePackage else { return }

        let viewport = viewportBox(for: route)
        let routeRect = CGRect(
            x: size.width * 0.08,
            y: size.height * 0.08,
            width: size.width * 0.84,
            height: size.height * 0.84
        )

        let progress = viewModel.navigationSnapshot?.progressDistanceMeters ?? 0
        let split = ActiveRouteMapOverlay.splitRouteCoordinates(route, atProgressMeters: progress)
        let actual = ActiveRouteMapOverlay.actualTrackCoordinates(from: viewModel)

        strokePath(
            context: &context,
            coordinates: split.remaining,
            viewport: viewport,
            routeRect: routeRect,
            color: .blue
        )
        strokePath(
            context: &context,
            coordinates: actual,
            viewport: viewport,
            routeRect: routeRect,
            color: .green
        )

        if let coordinate = viewModel.displayCoordinate {
            let point = pointForCoordinate(
                ActiveRouteMapOverlay.clLocation(coordinate),
                viewport: viewport,
                routeRect: routeRect
            )
            var dot = Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
            context.fill(dot, with: .color(.blue))
            context.stroke(dot, with: .color(.white), lineWidth: 2)
        }
    }

    private func viewportBox(for route: RoutePackage) -> GeoBoundingBox {
        if let center = viewModel.displayCoordinate, preferences.mapFollowMode {
            let halfSpan = uiState.mapSpan / 2
            return GeoBoundingBox(
                minLatitude: center.latitude - halfSpan,
                maxLatitude: center.latitude + halfSpan,
                minLongitude: center.longitude - halfSpan,
                maxLongitude: center.longitude + halfSpan
            )
        }
        return route.boundingBox
    }

    private func pointForCoordinate(
        _ coordinate: CLLocationCoordinate2D,
        viewport: GeoBoundingBox,
        routeRect: CGRect
    ) -> CGPoint {
        let nx = (coordinate.longitude - viewport.minLongitude)
            / max(0.0001, viewport.maxLongitude - viewport.minLongitude)
        let ny = 1 - (coordinate.latitude - viewport.minLatitude)
            / max(0.0001, viewport.maxLatitude - viewport.minLatitude)
        return CGPoint(
            x: routeRect.minX + routeRect.width * nx,
            y: routeRect.minY + routeRect.height * ny
        )
    }

    private func strokePath(
        context: inout GraphicsContext,
        coordinates: [CLLocationCoordinate2D],
        viewport: GeoBoundingBox,
        routeRect: CGRect,
        color: Color
    ) {
        guard coordinates.count >= 2 else { return }
        var path = Path()
        for (index, coordinate) in coordinates.enumerated() {
            let point = pointForCoordinate(coordinate, viewport: viewport, routeRect: routeRect)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        context.stroke(
            path,
            with: .color(RouteAppearance.routeOutlineColor),
            style: StrokeStyle(lineWidth: RouteAppearance.routeOutlineWidth, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: RouteAppearance.routeStrokeWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private func followLocationIfNeeded() {
        guard !isFocused else { return }
        recenterIfNeeded()
    }

    private func recenterIfNeeded() {
        guard !isFocused else { return }
        guard let coordinate = viewModel.displayCoordinate else { return }
        guard preferences.mapFollowMode else { return }

        let policy = batteryPolicy.displayUpdatePolicy
        guard viewModel.displayUpdateCoordinator.shouldRecenter(
            policy: policy,
            coordinate: coordinate,
            isMapVisible: isMapVisible,
            followEnabled: preferences.mapFollowMode
        ) else {
            return
        }

        viewModel.displayUpdateCoordinator.recordRecenter(at: coordinate)
        recenterToken += 1
    }
}
