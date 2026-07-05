import Foundation

public enum BatteryPreferredStartPage: String, Codable, Sendable {
    case directions
}

public struct BatteryModePolicy: Sendable, Equatable {
    public let mode: BatteryMode
    public let distanceFilterMeters: Double
    public let recordingAccuracyMeters: Double
    public let mapRecenterMinInterval: TimeInterval
    public let mapRecenterMinDistanceMeters: Double
    public let widgetReloadMinInterval: TimeInterval
    public let persistenceMinInterval: TimeInterval
    public let preferredStartPage: BatteryPreferredStartPage?
    public let suggestedMapDisplayMode: MapDisplayMode?
    public let allowsHeadingUpRotation: Bool
    public let updatesMapWhenHidden: Bool
    public let enablesBrowseWarmup: Bool
    public let usesReducedBrowseWarmup: Bool

    public init(mode: BatteryMode) {
        self.mode = mode
        switch mode {
        case .normal:
            distanceFilterMeters = 5
            recordingAccuracyMeters = 50
            mapRecenterMinInterval = 0
            mapRecenterMinDistanceMeters = 0
            widgetReloadMinInterval = 15
            persistenceMinInterval = 2
            preferredStartPage = nil
            suggestedMapDisplayMode = nil
            allowsHeadingUpRotation = true
            updatesMapWhenHidden = false
            enablesBrowseWarmup = true
            usesReducedBrowseWarmup = false
        case .saver:
            distanceFilterMeters = 12
            recordingAccuracyMeters = 80
            mapRecenterMinInterval = 2.5
            mapRecenterMinDistanceMeters = 10
            widgetReloadMinInterval = 30
            persistenceMinInterval = 3
            preferredStartPage = .directions
            suggestedMapDisplayMode = nil
            allowsHeadingUpRotation = true
            updatesMapWhenHidden = false
            enablesBrowseWarmup = true
            usesReducedBrowseWarmup = true
        case .ultraSaver:
            distanceFilterMeters = 25
            recordingAccuracyMeters = 150
            mapRecenterMinInterval = 5
            mapRecenterMinDistanceMeters = 25
            widgetReloadMinInterval = 75
            persistenceMinInterval = 5
            preferredStartPage = .directions
            suggestedMapDisplayMode = .routeOnly
            allowsHeadingUpRotation = false
            updatesMapWhenHidden = false
            enablesBrowseWarmup = false
            usesReducedBrowseWarmup = false
        }
    }

    public var displayUpdatePolicy: DisplayUpdatePolicy {
        DisplayUpdatePolicy(
            recenterMinInterval: mapRecenterMinInterval,
            recenterMinDistanceMeters: mapRecenterMinDistanceMeters,
            allowsHeadingUpRotation: allowsHeadingUpRotation,
            updatesWhenMapHidden: updatesMapWhenHidden
        )
    }

    public static func effective(userMode: BatteryMode, lowPowerModeEnabled: Bool) -> BatteryMode {
        guard lowPowerModeEnabled else { return userMode }
        switch userMode {
        case .normal:
            return .saver
        case .saver, .ultraSaver:
            return userMode
        }
    }

    public static func policy(
        userMode: BatteryMode,
        lowPowerModeEnabled: Bool = LowPowerModeStatus.isEnabled
    ) -> BatteryModePolicy {
        BatteryModePolicy(mode: effective(userMode: userMode, lowPowerModeEnabled: lowPowerModeEnabled))
    }
}

public enum LowPowerModeStatus {
    public static var isEnabled: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}
