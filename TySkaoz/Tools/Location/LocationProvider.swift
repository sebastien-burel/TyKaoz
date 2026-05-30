import CoreLocation
import Foundation

/// Errors surfaced by the location tool to the model. Each maps to a clear
/// reason the user can act on (grant permission, reconnect, etc.).
enum LocationError: Error, LocalizedError, Equatable {
    case denied
    case restricted
    case unavailable(message: String)

    var errorDescription: String? {
        switch self {
        case .denied:
            return "Accès à la localisation refusé. Autorisez TyKaoz dans Réglages système → Confidentialité → Localisation."
        case .restricted:
            return "Accès à la localisation restreint par la configuration de l'appareil."
        case .unavailable(let message):
            return "Localisation indisponible : \(message)"
        }
    }
}

/// Abstracts the underlying Core Location bits so the tool stays testable.
protocol LocationProviding: Sendable {
    func currentLocation() async throws -> CLLocation
}

/// Uses `CLLocationUpdate.liveUpdates()` for the actual fix because the
/// delegate-based API was unreliable in practice: `requestLocation()` aborts
/// on the first transient `kCLErrorLocationUnknown`, and re-using
/// `startUpdatingLocation()` after a previous stop sometimes never re-delivers
/// an event. `CLServiceSession` would be the iOS path here; on macOS we still
/// drive authorization through `CLLocationManager`.
@MainActor
final class AppleLocationProvider: NSObject, CLLocationManagerDelegate, LocationProviding {
    static let shared = AppleLocationProvider()

    private static let fixTimeout: Duration = .seconds(15)
    private static let cachedFixMaxAge: TimeInterval = 60

    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var lastFix: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
    }

    func currentLocation() async throws -> CLLocation {
        if let cached = lastFix,
           cached.horizontalAccuracy >= 0,
           -cached.timestamp.timeIntervalSinceNow <= Self.cachedFixMaxAge {
            return cached
        }

        let status = await ensureAuthorized()
        switch status {
        case .denied:     throw LocationError.denied
        case .restricted: throw LocationError.restricted
        default:          break
        }

        return try await withThrowingTaskGroup(of: CLLocation.self) { group in
            group.addTask { @MainActor [weak self] in
                for try await update in CLLocationUpdate.liveUpdates() {
                    if update.authorizationDenied || update.authorizationDeniedGlobally {
                        throw LocationError.denied
                    }
                    if update.authorizationRestricted {
                        throw LocationError.restricted
                    }
                    if let location = update.location,
                       location.horizontalAccuracy >= 0 {
                        self?.lastFix = location
                        return location
                    }
                }
                throw LocationError.unavailable(message: "flux interrompu sans fix")
            }
            group.addTask {
                try await Task.sleep(for: Self.fixTimeout)
                throw LocationError.unavailable(
                    message: "aucun fix obtenu dans le délai imparti"
                )
            }

            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw LocationError.unavailable(message: "flux vide")
            }
            return first
        }
    }

    private func ensureAuthorized() async -> CLAuthorizationStatus {
        let current = manager.authorizationStatus
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard manager.authorizationStatus != .notDetermined,
                  let continuation = authorizationContinuation else { return }
            authorizationContinuation = nil
            continuation.resume(returning: manager.authorizationStatus)
        }
    }
}
