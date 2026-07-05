import Foundation

public struct LocationQualityInput: Sendable, Hashable {
    public let latitude: Double
    public let longitude: Double
    public let horizontalAccuracyMeters: Double
    public let speedMetersPerSecond: Double?
    public let timestamp: Date

    public init(
        latitude: Double,
        longitude: Double,
        horizontalAccuracyMeters: Double,
        speedMetersPerSecond: Double? = nil,
        timestamp: Date
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.speedMetersPerSecond = speedMetersPerSecond
        self.timestamp = timestamp
    }
}

public enum LocationQualityMode: Sendable {
    case warmup
    case recording
}

public enum LocationQualityRejection: Sendable, Equatable {
    case invalidCoordinate
    case staleFix(ageSeconds: TimeInterval)
    case poorAccuracy(horizontalAccuracyMeters: Double, thresholdMeters: Double)
    case excessiveSpeed(impliedSpeedMetersPerSecond: Double, maxSpeedMetersPerSecond: Double)
}

public enum LocationQualityOutcome: Sendable, Equatable {
    case rejected(LocationQualityRejection)
    case previewOnly
    case accepted
}

public struct LocationQualityFilter: Sendable {
    public static let maxStaleAgeSeconds: TimeInterval = 5
    public static let requiredConsecutiveGoodFixes = 2
    public static let maxStabilizationSeparationMeters = 30.0
    public static let warmupPreviewAccuracyMeters = 100.0

    private var isStabilized = false
    private var consecutiveGoodFixes = 0
    private var lastCandidateCoordinate: GeoCoordinate?
    private var lastAcceptedCoordinate: GeoCoordinate?
    private var lastAcceptedTimestamp: Date?

    public init() {}

    public var hasStabilized: Bool { isStabilized }

    public mutating func reset(startingStabilized: Bool = false, seed: LocationQualityInput? = nil) {
        isStabilized = startingStabilized
        consecutiveGoodFixes = startingStabilized ? Self.requiredConsecutiveGoodFixes : 0
        lastCandidateCoordinate = nil

        if let seed, startingStabilized, MapMath.isValidCoordinate(latitude: seed.latitude, longitude: seed.longitude) {
            lastAcceptedCoordinate = GeoCoordinate(latitude: seed.latitude, longitude: seed.longitude)
            lastAcceptedTimestamp = seed.timestamp
        } else {
            lastAcceptedCoordinate = nil
            lastAcceptedTimestamp = nil
        }
    }

    public func isWarmupReady(
        input: LocationQualityInput,
        activityKind: ActivityKind,
        referenceDate: Date = Date()
    ) -> Bool {
        guard MapMath.isValidCoordinate(latitude: input.latitude, longitude: input.longitude) else { return false }
        guard !isStale(input: input, referenceDate: referenceDate) else { return false }
        return input.horizontalAccuracyMeters <= activityKind.gpsStabilizationAccuracyMeters
    }

    public mutating func evaluate(
        input: LocationQualityInput,
        activityKind: ActivityKind,
        batteryMode: BatteryMode,
        mode: LocationQualityMode,
        referenceDate: Date = Date()
    ) -> LocationQualityOutcome {
        guard MapMath.isValidCoordinate(latitude: input.latitude, longitude: input.longitude) else {
            return .rejected(.invalidCoordinate)
        }

        if isStale(input: input, referenceDate: referenceDate) {
            let age = referenceDate.timeIntervalSince(input.timestamp)
            return .rejected(.staleFix(ageSeconds: age))
        }

        let coordinate = GeoCoordinate(latitude: input.latitude, longitude: input.longitude)
        let accuracyThreshold = accuracyThresholdMeters(
            activityKind: activityKind,
            batteryMode: batteryMode,
            mode: mode,
            isStabilized: isStabilized
        )

        if input.horizontalAccuracyMeters > accuracyThreshold {
            return .rejected(.poorAccuracy(
                horizontalAccuracyMeters: input.horizontalAccuracyMeters,
                thresholdMeters: accuracyThreshold
            ))
        }

        if mode == .warmup {
            return .previewOnly
        }

        if let rejection = speedRejection(
            input: input,
            coordinate: coordinate,
            activityKind: activityKind
        ) {
            return .rejected(rejection)
        }

        if !isStabilized {
            return advanceStabilization(with: coordinate, timestamp: input.timestamp)
        }

        lastAcceptedCoordinate = coordinate
        lastAcceptedTimestamp = input.timestamp
        return .accepted
    }

    private mutating func advanceStabilization(
        with coordinate: GeoCoordinate,
        timestamp: Date
    ) -> LocationQualityOutcome {
        if let previous = lastCandidateCoordinate {
            let separation = MapMath.haversineMeters(from: previous, to: coordinate)
            if separation > Self.maxStabilizationSeparationMeters {
                consecutiveGoodFixes = 1
            } else {
                consecutiveGoodFixes += 1
            }
        } else {
            consecutiveGoodFixes = 1
        }

        lastCandidateCoordinate = coordinate

        if consecutiveGoodFixes >= Self.requiredConsecutiveGoodFixes {
            isStabilized = true
            lastAcceptedCoordinate = coordinate
            lastAcceptedTimestamp = timestamp
            return .accepted
        }

        return .previewOnly
    }

    private func isStale(input: LocationQualityInput, referenceDate: Date) -> Bool {
        referenceDate.timeIntervalSince(input.timestamp) > Self.maxStaleAgeSeconds
    }

    private func accuracyThresholdMeters(
        activityKind: ActivityKind,
        batteryMode: BatteryMode,
        mode: LocationQualityMode,
        isStabilized: Bool
    ) -> Double {
        switch mode {
        case .warmup:
            return Self.warmupPreviewAccuracyMeters
        case .recording:
            if isStabilized {
                return batteryMode.gpsRecordingAccuracyMeters
            }
            return activityKind.gpsStabilizationAccuracyMeters
        }
    }

    private func speedRejection(
        input: LocationQualityInput,
        coordinate: GeoCoordinate,
        activityKind: ActivityKind
    ) -> LocationQualityRejection? {
        guard let previous = lastAcceptedCoordinate,
              let previousTimestamp = lastAcceptedTimestamp else {
            return nil
        }

        let elapsed = input.timestamp.timeIntervalSince(previousTimestamp)
        guard elapsed > 0 else { return nil }

        let distance = MapMath.haversineMeters(from: previous, to: coordinate)
        let impliedSpeed = distance / elapsed
        let reportedSpeed = input.speedMetersPerSecond ?? -1
        let effectiveSpeed = reportedSpeed >= 0 ? max(impliedSpeed, reportedSpeed) : impliedSpeed
        let maxSpeed = activityKind.maximumPlausibleSpeedMetersPerSecond

        guard effectiveSpeed > maxSpeed else { return nil }
        return .excessiveSpeed(
            impliedSpeedMetersPerSecond: effectiveSpeed,
            maxSpeedMetersPerSecond: maxSpeed
        )
    }
}

public enum GPSAcquisitionState: String, Sendable, Equatable {
    case idle
    case warmingUp
    case acquiring
    case ready
}

extension ActivityKind {
    public var gpsStabilizationAccuracyMeters: Double {
        switch speedCategory {
        case .running: 25
        case .cycling: 30
        }
    }

    public var maximumPlausibleSpeedMetersPerSecond: Double {
        switch self {
        case .running, .trailRunning: 8
        case .gravelCycling: 18
        case .roadCycling: 25
        }
    }
}

extension BatteryMode {
    public var gpsRecordingAccuracyMeters: Double {
        switch self {
        case .normal: 50
        case .saver: 80
        case .ultraSaver: 150
        }
    }
}
