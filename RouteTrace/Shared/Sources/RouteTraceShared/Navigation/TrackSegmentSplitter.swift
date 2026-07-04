import Foundation

public struct TrackSegment: Sendable, Hashable {
    public let coordinates: [GeoCoordinate]
    public let isGapConnector: Bool

    public init(coordinates: [GeoCoordinate], isGapConnector: Bool) {
        self.coordinates = coordinates
        self.isGapConnector = isGapConnector
    }
}

public enum TrackSegmentSplitter {
    public static let defaultTimeGapSeconds: TimeInterval = 60
    public static let defaultSpatialJumpMeters: Double = 150

    /// Splits track points into renderable segments, inserting gap connectors between breaks.
    public static func segments(
        from trackPoints: [TrackPoint],
        timeGapSeconds: TimeInterval = defaultTimeGapSeconds,
        spatialJumpMeters: Double = defaultSpatialJumpMeters
    ) -> [TrackSegment] {
        let continuous = continuousSegments(
            from: trackPoints,
            timeGapSeconds: timeGapSeconds,
            spatialJumpMeters: spatialJumpMeters
        )
        guard !continuous.isEmpty else { return [] }

        var result: [TrackSegment] = []
        for (index, segmentPoints) in continuous.enumerated() {
            let coordinates = segmentPoints.map(\.coordinate)
            guard coordinates.count >= 2 else { continue }
            result.append(TrackSegment(coordinates: coordinates, isGapConnector: false))

            if index < continuous.count - 1 {
                let nextSegment = continuous[index + 1]
                guard let last = segmentPoints.last, let first = nextSegment.first else { continue }
                result.append(
                    TrackSegment(
                        coordinates: [last.coordinate, first.coordinate],
                        isGapConnector: true
                    )
                )
            }
        }
        return result
    }

    /// Returns uninterrupted recording periods for GPX export (no gap connectors).
    public static func continuousSegments(
        from trackPoints: [TrackPoint],
        timeGapSeconds: TimeInterval = defaultTimeGapSeconds,
        spatialJumpMeters: Double = defaultSpatialJumpMeters
    ) -> [[TrackPoint]] {
        guard !trackPoints.isEmpty else { return [] }

        var segments: [[TrackPoint]] = []
        var current: [TrackPoint] = [trackPoints[0]]

        for index in 1..<trackPoints.count {
            let previous = trackPoints[index - 1]
            let point = trackPoints[index]
            let timeGap = point.timestamp.timeIntervalSince(previous.timestamp)
            let spatialJump = MapMath.haversineMeters(from: previous.coordinate, to: point.coordinate)

            if timeGap > timeGapSeconds || spatialJump > spatialJumpMeters {
                if current.count >= 1 {
                    segments.append(current)
                }
                current = [point]
            } else {
                current.append(point)
            }
        }

        if !current.isEmpty {
            segments.append(current)
        }
        return segments.filter { $0.count >= 1 }
    }
}
