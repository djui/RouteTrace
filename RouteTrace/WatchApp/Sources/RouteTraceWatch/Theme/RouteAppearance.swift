import SwiftUI

enum RouteAppearance {
    static func canvas(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color.black
        default:
            Color(white: 0.96)
        }
    }

    static var overlayGlass: Glass {
        .regular
    }

    static var overlayText: Color {
        .primary
    }

    static var pageDotInactive: Color {
        Color.secondary.opacity(0.45)
    }

    static func pageDotActive(for page: RoutePage) -> Color {
        switch page {
        case .controls:
            .orange
        case .liveMap:
            .blue
        case .directions:
            .green
        case .altitude:
            .cyan
        case .metrics:
            Color.primary
        }
    }

    static func offlineMapCanvas(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(white: 0.12)
        default:
            Color(white: 0.92)
        }
    }

    static func chartProgressFill(for colorScheme: ColorScheme) -> Color {
        Color.secondary.opacity(colorScheme == .dark ? 0.2 : 0.12)
    }

    static func dimmedOverlay(for colorScheme: ColorScheme) -> Color {
        canvas(for: colorScheme).opacity(colorScheme == .dark ? 1 : 0.2)
    }

    static let routeOutlineWidth: CGFloat = 7
    static let routeStrokeWidth: CGFloat = 4.5
    static let routeOutlineColor = Color.black.opacity(0.55)

    /// Top-leading controls (X) — keep clear of large corner radius.
    static let watchCornerClearance: CGFloat = 12

    /// Top/bottom chrome sitting near flat edges (not extreme corners).
    static let watchEdgeInset: CGFloat = 2

    /// Floating bottom buttons — clear large watch corner radius while staying low.
    static let watchFloatingButtonBottomInset: CGFloat = 12

    /// Horizontal inset for full-width bottom overlays to clear corner radius.
    static let watchOverlayHorizontalInset: CGFloat = 12

    /// Centered map distance bubble — below system time and status icons.
    static let watchMapDistanceTopInset: CGFloat = 38

    /// Crown zoom step per detent — smaller = finer zoom increments.
    static let mapCrownStep: Double = 0.001

    static func elevationGradeColor(
        elevationDelta: Double,
        distanceDelta: Double,
        colorScheme: ColorScheme
    ) -> Color {
        guard distanceDelta > 0 else { return .gray }

        let grade = elevationDelta / distanceDelta
        if grade < 0 {
            return colorScheme == .dark ? Color.white.opacity(0.85) : Color(white: 0.72)
        }
        if grade < 0.02 { return .green }
        if grade < 0.05 { return .yellow }
        if grade < 0.10 { return .orange }
        return .red
    }
}

struct RouteGlassIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(RouteAppearance.overlayText.opacity(0.85))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }
}

extension View {
    func routeScreenBackground() -> some View {
        background {
            RouteScreenBackground()
        }
    }

    @ViewBuilder
    func conditionalRouteScreenBackground(isOpaque: Bool) -> some View {
        if isOpaque {
            routeScreenBackground()
        } else {
            self
        }
    }

    func routeOverlayBackground<S: Shape>(in shape: S) -> some View {
        glassEffect(RouteAppearance.overlayGlass, in: shape)
    }

    @ViewBuilder
    func routeGlassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        if prominent {
            if let tint {
                self.buttonStyle(.glassProminent).tint(tint)
            } else {
                self.buttonStyle(.glassProminent)
            }
        } else if let tint {
            self.buttonStyle(.glass).tint(tint)
        } else {
            self.buttonStyle(.glass)
        }
    }
}

private struct RouteScreenBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RouteAppearance.canvas(for: colorScheme)
    }
}
