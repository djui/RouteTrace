import CoreTransferable
import RouteTraceShared
import SwiftUI
import UniformTypeIdentifiers

/// Visual language shared across screens: the planned route is blue, the recorded track green
/// (as in the app icon), content sits on softly rounded cards.
enum RouteDesign {
    static let routeColor = Color.blue
    static let trackColor = Color.green
    static let cardCornerRadius: CGFloat = 22
    static let thumbnailCornerRadius: CGFloat = 14
}

// MARK: - Cards

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: RouteDesign.cardCornerRadius, style: .continuous)
            )
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardBackground(padding: padding))
    }
}

struct CardHeader: View {
    let title: String
    var systemImage: String?
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.headline)
    }
}

// MARK: - Stats

/// A headline figure, e.g. "16.0 km" over "Distance".
struct HeadlineStat: View {
    let title: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A compact grid cell for secondary figures.
struct StatCell: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.body.weight(.semibold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Chips

struct StatusChip: View {
    let title: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .imageScale(.small)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(tint)
        .background(tint.opacity(0.13), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Route shape

/// Draws a polyline to scale (equirectangular, aspect preserved), centered in its frame.
///
/// The previous thumbnails stretched latitude and longitude independently to fill a square,
/// which distorted every route shape.
struct RouteShape: Shape {
    let coordinates: [GeoCoordinate]
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard coordinates.count >= 2, let project = Self.projector(for: coordinates, in: rect.insetBy(dx: inset, dy: inset)) else {
            return path
        }
        for (index, coordinate) in coordinates.enumerated() {
            if index == 0 {
                path.move(to: project(coordinate))
            } else {
                path.addLine(to: project(coordinate))
            }
        }
        return path
    }

    /// Maps coordinates into `rect`, scaled uniformly to fit the bounding box of `coordinates`.
    static func projector(
        for coordinates: [GeoCoordinate],
        in rect: CGRect
    ) -> ((GeoCoordinate) -> CGPoint)? {
        guard let box = MapMath.boundingBox(for: coordinates) else { return nil }
        let longitudeScale = cos(box.center.latitude * .pi / 180)
        let width = max((box.maxLongitude - box.minLongitude) * longitudeScale, 1e-9)
        let height = max(box.maxLatitude - box.minLatitude, 1e-9)
        let scale = min(rect.width / width, rect.height / height)
        let originX = rect.midX - width * scale / 2
        let originY = rect.midY - height * scale / 2
        return { coordinate in
            CGPoint(
                x: originX + (coordinate.longitude - box.minLongitude) * longitudeScale * scale,
                y: originY + (box.maxLatitude - coordinate.latitude) * scale
            )
        }
    }
}

struct RouteShapeThumbnail: View {
    let coordinates: [GeoCoordinate]
    var color: Color = RouteDesign.routeColor
    var size: CGFloat = 64
    var placeholderSymbol = "point.bottomleft.forward.to.point.topright.scurvepath"

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: RouteDesign.thumbnailCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.16), color.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if coordinates.count >= 2 {
                RouteShape(coordinates: coordinates, inset: size * 0.16)
                    .stroke(color, style: StrokeStyle(lineWidth: max(2, size / 26), lineCap: .round, lineJoin: .round))

                if let start = coordinates.first {
                    Circle()
                        .fill(.white)
                        .stroke(color, lineWidth: 1.5)
                        .frame(width: size / 11, height: size / 11)
                        .position(endpointPosition(start, in: CGSize(width: size, height: size)))
                }
            } else {
                Image(systemName: placeholderSymbol)
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(color.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func endpointPosition(_ coordinate: GeoCoordinate, in size: CGSize) -> CGPoint {
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.16, dy: size.height * 0.16)
        return RouteShape.projector(for: coordinates, in: rect)?(coordinate)
            ?? CGPoint(x: size.width / 2, y: size.height / 2)
    }
}

// MARK: - Transient banner

/// Non-modal confirmation shown at the top of the screen for a few seconds.
struct TransientBanner: View {
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(message)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 24)
        .accessibilityAddTraits(.isStaticText)
    }
}

struct TransientBannerModifier: ViewModifier {
    @Binding var banner: BannerContent?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let banner {
                TransientBanner(message: banner.message, systemImage: banner.systemImage, tint: banner.tint)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(banner.id)
                    .task(id: banner.id) {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation(.snappy) { self.banner = nil }
                    }
                    .onTapGesture {
                        withAnimation(.snappy) { self.banner = nil }
                    }
            }
        }
        .animation(.snappy, value: banner?.id)
    }
}

struct BannerContent: Equatable {
    let id = UUID()
    let message: String
    let systemImage: String
    let tint: Color
}

extension View {
    func transientBanner(_ banner: Binding<BannerContent?>) -> some View {
        modifier(TransientBannerModifier(banner: banner))
    }
}

// MARK: - Sharing

extension UTType {
    static let gpx = UTType(importedAs: "com.topografix.gpx", conformingTo: .xml)
}

/// A GPX document generated on demand when shared, so no temp file needs managing.
struct GPXDocument: Transferable {
    let fileName: String
    let contents: @Sendable () throws -> String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .gpx) { document in
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(sanitizedFileName(document.fileName)).appendingPathExtension("gpx")
            try document.contents().write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }

    static func route(_ package: RoutePackage) -> GPXDocument {
        GPXDocument(fileName: package.name) { GPXExporter.exportRoute(package) }
    }

    static func activity(_ recording: ActivityRecording) -> GPXDocument {
        GPXDocument(fileName: recording.displayTitle) {
            GPXExporter.exportActivity(recording, route: nil)
        }
    }

    private static func sanitizedFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Route" : String(cleaned.prefix(80))
    }
}

// MARK: - Labels for model state

extension ActivityKind {
    var tint: Color {
        switch self {
        case .running: .orange
        case .trailRunning: .brown
        case .roadCycling: .indigo
        case .gravelCycling: .teal
        }
    }
}

extension TransferState {
    var displayName: String {
        switch self {
        case .notSent: "Not on Watch"
        case .queued: "Queued"
        case .transferring: "Sending…"
        case .installed: "On Watch"
        case .failed: "Send Failed"
        case .removedFromWatch: "Removed from Watch"
        }
    }

    var systemImage: String {
        switch self {
        case .notSent, .removedFromWatch: "applewatch.slash"
        case .queued, .transferring: "applewatch.radiowaves.left.and.right"
        case .installed: "applewatch"
        case .failed: "exclamationmark.applewatch"
        }
    }

    var tint: Color {
        switch self {
        case .notSent, .removedFromWatch: .secondary
        case .queued, .transferring: .orange
        case .installed: .green
        case .failed: .red
        }
    }

    var canSend: Bool {
        switch self {
        case .notSent, .failed, .removedFromWatch, .installed: true
        case .queued, .transferring: false
        }
    }
}

extension OfflinePackStatus {
    var displayName: String {
        switch self {
        case .missing: "No Offline Map"
        case .partial: "Partial Offline Map"
        case .ready: "Offline Map"
        }
    }

    var systemImage: String {
        switch self {
        case .missing: "map"
        case .partial: "exclamationmark.triangle"
        case .ready: "map.fill"
        }
    }

    var tint: Color {
        switch self {
        case .missing: .secondary
        case .partial: .orange
        case .ready: .blue
        }
    }
}
