import Foundation

#if os(iOS)
import CoreLocation
import os

enum KeepAliveError: Error {
    case locationDenied
}

/// Keeps the app alive in the background during Drive Mode via a low-power
/// background location session.
///
/// Location, NOT silent audio, on purpose: iOS explicitly forbids Live
/// Activity updates from processes whose only background reason is playing
/// media ("Process is only playing background media so is forbidden to
/// update activity" — liveactivitiesd). A location session grants normal
/// background execution AND update permission, which is how navigation apps
/// update their Live Activities. Accuracy is deliberately coarse — the fix
/// keeps the process alive; the positions are irrelevant and never stored.
///
/// ⚠️ App Store note (CLAUDE.md §6): using location purely as a keep-alive
/// would be rejected in App Review. Fine for a personally sideloaded build;
/// a store build would need push-updated activities instead.
final class BackgroundKeeper: NSObject, CLLocationManagerDelegate {
    private static let log = Logger(subsystem: "com.praveet.driveverse", category: "keepalive")

    private let manager = CLLocationManager()
    private var wantsRunning = false
    private(set) var isRunning = false

    /// Surfaced on the Home screen when a permission problem blocks Drive Mode.
    var onIssue: ((String) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        // Cheapest possible session: cell-tower accuracy, no GPS spin-up.
        // The session's existence is what keeps the app alive — the fixes
        // themselves are discarded, so precision buys nothing but battery.
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = 1_000
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .automotiveNavigation
    }

    func start() throws {
        guard !isRunning else { return }
        wantsRunning = true
        switch manager.authorizationStatus {
        case .notDetermined:
            // activate() follows from the delegate callback once granted.
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            wantsRunning = false
            throw KeepAliveError.locationDenied
        default:
            activate()
        }
    }

    func stop() {
        wantsRunning = false
        guard isRunning else { return }
        isRunning = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    private func activate() {
        guard wantsRunning, !isRunning else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        isRunning = true
        // "Always" lets the CarPlay automation start Drive Mode with the app
        // launched straight into the background; When-In-Use is enough for
        // sessions begun in the foreground.
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard wantsRunning else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            activate()
        case .denied, .restricted:
            wantsRunning = false
            onIssue?("Drive Mode needs location access to stay alive in the background. Allow it for DriveVerse in Settings → Privacy → Location Services.")
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Self.log.warning("location error: \(error.localizedDescription, privacy: .public)")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Positions are irrelevant and discarded — the session's existence is
        // the feature.
    }
}
#endif
