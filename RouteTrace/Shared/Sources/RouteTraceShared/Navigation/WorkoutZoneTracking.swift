import Foundation

/// A stretch of recorded track spent in one zone, for drawing the track in zone colours.
public struct ZonedTrackSegment: Sendable, Hashable {
    public let coordinates: [GeoCoordinate]
    /// Nil before the first reading, or across a recording gap.
    public let zoneIndex: Int?
    public let isGapConnector: Bool

    public init(coordinates: [GeoCoordinate], zoneIndex: Int?, isGapConnector: Bool) {
        self.coordinates = coordinates
        self.zoneIndex = zoneIndex
        self.isGapConnector = isGapConnector
    }
}

public enum ZonedTrackSegmenter {
    /// Runs shorter than this take the zone of the run before them, so a heart rate hovering at a
    /// boundary doesn't cut the track into confetti (and hundreds of map overlays).
    public static let defaultMinimumRunSeconds: TimeInterval = 20

    /// Splits the track wherever the zone of the recorded reading changes, with the same gap
    /// handling as `TrackSegmentSplitter`. Points without a reading keep the zone before them.
    public static func segments(
        from trackPoints: [TrackPoint],
        zones: WorkoutZones,
        reading: (TrackPoint) -> Double? = \.heartRateBPM,
        minimumRunSeconds: TimeInterval = defaultMinimumRunSeconds
    ) -> [ZonedTrackSegment] {
        let continuous = TrackSegmentSplitter.continuousSegments(from: trackPoints)
        var result: [ZonedTrackSegment] = []

        for (index, points) in continuous.enumerated() {
            guard points.count >= 2 else { continue }
            result += zoneRuns(in: points, zones: zones, reading: reading, minimumRunSeconds: minimumRunSeconds)

            if index < continuous.count - 1, let last = points.last, let next = continuous[index + 1].first {
                result.append(ZonedTrackSegment(
                    coordinates: [last.coordinate, next.coordinate],
                    zoneIndex: nil,
                    isGapConnector: true
                ))
            }
        }
        return result
    }

    private struct Run {
        var start: Int
        var end: Int
        var zoneIndex: Int?
    }

    private static func zoneRuns(
        in points: [TrackPoint],
        zones: WorkoutZones,
        reading: (TrackPoint) -> Double?,
        minimumRunSeconds: TimeInterval
    ) -> [ZonedTrackSegment] {
        var runs: [Run] = []
        var currentZone: Int?
        for (index, point) in points.enumerated() {
            if let value = reading(point), value.isFinite {
                currentZone = zones.zoneIndex(for: value)
            }
            if let last = runs.last, last.zoneIndex == currentZone {
                runs[runs.count - 1].end = index
            } else {
                runs.append(Run(start: index, end: index, zoneIndex: currentZone))
            }
        }

        func seconds(_ run: Run) -> TimeInterval {
            points[run.end].timestamp.timeIntervalSince(points[run.start].timestamp)
        }

        var merged: [Run] = []
        for run in runs {
            guard let last = merged.last else {
                merged.append(run)
                continue
            }
            if last.zoneIndex == run.zoneIndex || seconds(run) < minimumRunSeconds {
                merged[merged.count - 1].end = run.end
            } else if merged.count == 1, seconds(last) < minimumRunSeconds {
                // A short opening run can't take a previous zone; the next one absorbs it.
                merged[0] = Run(start: last.start, end: run.end, zoneIndex: run.zoneIndex)
            } else {
                merged.append(run)
            }
        }

        // Each run starts at the last point of the one before, so the drawn line stays unbroken.
        return merged.enumerated().compactMap { index, run in
            let first = index == 0 ? run.start : merged[index - 1].end
            let coordinates = points[first...run.end].map(\.coordinate)
            guard coordinates.count >= 2 else { return nil }
            return ZonedTrackSegment(coordinates: coordinates, zoneIndex: run.zoneIndex, isGapConnector: false)
        }
    }
}

/// Decides when a zone change is worth a haptic: the new zone has to hold for a while and
/// alerts are spaced out, so a heart rate hovering at a boundary doesn't buzz every few seconds.
public struct ZoneChangeAlertPolicy: Sendable {
    public enum Change: Equatable, Sendable {
        case up(toZone: Int)
        case down(toZone: Int)
    }

    public static let defaultDwellSeconds: TimeInterval = 20
    public static let defaultCooldownSeconds: TimeInterval = 60

    public let dwellSeconds: TimeInterval
    public let cooldownSeconds: TimeInterval

    private var candidateZone: Int?
    private var candidateSince: Date?
    private var announcedZone: Int?
    private var lastAlertAt: Date?

    public init(
        dwellSeconds: TimeInterval = defaultDwellSeconds,
        cooldownSeconds: TimeInterval = defaultCooldownSeconds
    ) {
        self.dwellSeconds = dwellSeconds
        self.cooldownSeconds = cooldownSeconds
    }

    public mutating func reset() {
        candidateZone = nil
        candidateSince = nil
        announcedZone = nil
        lastAlertAt = nil
    }

    /// Feeds the current zone. Returns the change to announce, if any.
    ///
    /// The first zone that settles is the baseline and isn't announced. While `canAlert` is false
    /// (another haptic just played) a due change waits instead of being dropped.
    public mutating func update(zoneIndex: Int?, at date: Date, canAlert: Bool = true) -> Change? {
        guard let zoneIndex else {
            candidateZone = nil
            candidateSince = nil
            return nil
        }
        if candidateZone != zoneIndex {
            candidateZone = zoneIndex
            candidateSince = date
        }
        guard let since = candidateSince, date.timeIntervalSince(since) >= dwellSeconds else { return nil }

        guard let announced = announcedZone else {
            announcedZone = zoneIndex
            return nil
        }
        guard zoneIndex != announced, canAlert else { return nil }
        if let lastAlertAt, date.timeIntervalSince(lastAlertAt) < cooldownSeconds {
            return nil
        }

        announcedZone = zoneIndex
        lastAlertAt = date
        return zoneIndex > announced ? .up(toZone: zoneIndex) : .down(toZone: zoneIndex)
    }
}
