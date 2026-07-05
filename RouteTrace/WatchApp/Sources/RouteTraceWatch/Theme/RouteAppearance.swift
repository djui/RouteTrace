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

    static var overlayFill: Material {
        .ultraThinMaterial
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

    /// Horizontal inset for full-width bottom overlays to clear corner radius.
    static let watchOverlayHorizontalInset: CGFloat = 12

    /// Centered map distance bubble — below system time and status icons.
    static let watchMapDistanceTopInset: CGFloat = 20

    /// Crown zoom step per detent — smaller = finer zoom increments.
    static let mapCrownStep: Double = 0.001
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
}

private struct RouteScreenBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RouteAppearance.canvas(for: colorScheme)
    }
}
