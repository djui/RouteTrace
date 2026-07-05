import CoreLocation
import Foundation
import Observation
import RouteTraceShared

struct LocationSample: Sendable {
    let coordinate: CLLocationCoordinate2D
    let altitudeMeters: Double?
    let horizontalAccuracyMeters: Double
    let speedMetersPerSecond: Double?
    let courseDegrees: Double?
    let timestamp: Date
}

@MainActor
@Observable
final class LocationTrackingService: NSObject {
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var isTracking = false
    private(set) var lastSample: LocationSample?
    private(set) var lastError: String?

    var onLocationUpdate: (@MainActor (LocationSample) -> Void)?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = 5
        #if os(iOS)
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        #endif
        authorizationStatus = manager.authorizationStatus
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startTracking(distanceFilterMeters: CLLocationDistance = 5) {
        guard CLLocationManager.locationServicesEnabled() else {
            lastError = "Location services are disabled."
            return
        }

        manager.distanceFilter = distanceFilterMeters
        manager.startUpdatingLocation()
        isTracking = true
        lastError = nil
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        isTracking = false
    }

    func applyBatteryPolicy(_ policy: BatteryModePolicy) {
        switch policy.mode {
        case .normal:
            manager.desiredAccuracy = kCLLocationAccuracyBest
        case .saver:
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        case .ultraSaver:
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        }
        manager.distanceFilter = policy.distanceFilterMeters
    }

    func applyBatteryMode(_ mode: BatteryMode) {
        applyBatteryPolicy(BatteryModePolicy(mode: mode))
    }
}

extension LocationTrackingService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorizationStatus = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let sample = LocationSample(
            coordinate: location.coordinate,
            altitudeMeters: location.verticalAccuracy >= 0 ? location.altitude : nil,
            horizontalAccuracyMeters: max(location.horizontalAccuracy, 0),
            speedMetersPerSecond: location.speed >= 0 ? location.speed : nil,
            courseDegrees: location.course >= 0 ? location.course : nil,
            timestamp: location.timestamp
        )

        Task { @MainActor in
            lastSample = sample
            onLocationUpdate?(sample)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            lastError = error.localizedDescription
        }
    }
}
