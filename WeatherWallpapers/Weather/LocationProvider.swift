import Foundation
import CoreLocation

/// One-shot location with a cached fallback, so the Shortcuts intent keeps
/// working even when Core Location is unavailable in the background.
///
/// CLLocationManager must live on a thread with a run loop — everything that
/// touches it is funneled to the main thread.
final class LocationProvider: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = LocationProvider()

    private var manager: CLLocationManager!
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<CLLocation, Error>] = []

    private static let cachedLatKey = "lastKnownLatitude"
    private static let cachedLonKey = "lastKnownLongitude"

    override private init() {
        super.init()
        onMain {
            self.manager = CLLocationManager()
            self.manager.delegate = self
            self.manager.desiredAccuracy = kCLLocationAccuracyKilometer
        }
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    var authorizationStatus: CLAuthorizationStatus {
        var status: CLAuthorizationStatus = .notDetermined
        onMain { status = self.manager.authorizationStatus }
        return status
    }

    func requestAuthorization() {
        onMain { self.manager.requestWhenInUseAuthorization() }
    }

    var cachedCoordinate: CLLocationCoordinate2D? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.cachedLatKey) != nil else { return nil }
        return CLLocationCoordinate2D(
            latitude: defaults.double(forKey: Self.cachedLatKey),
            longitude: defaults.double(forKey: Self.cachedLonKey)
        )
    }

    /// Returns a fresh location, or the cached one if Core Location fails
    /// or does not answer within the timeout.
    func currentCoordinate(timeout: TimeInterval = 8) async -> CLLocationCoordinate2D? {
        do {
            let location = try await freshLocation(timeout: timeout)
            let defaults = UserDefaults.standard
            defaults.set(location.coordinate.latitude, forKey: Self.cachedLatKey)
            defaults.set(location.coordinate.longitude, forKey: Self.cachedLonKey)
            return location.coordinate
        } catch {
            return cachedCoordinate
        }
    }

    /// Refreshes the cached coordinate in the background (used by the app UI
    /// so the intent always has something to fall back to).
    func warmUpCache() {
        Task.detached(priority: .utility) { [weak self] in
            _ = await self?.currentCoordinate()
        }
    }

    private func freshLocation(timeout: TimeInterval) async throws -> CLLocation {
        let status = authorizationStatus
        #if os(macOS)
        let authorized = status == .authorized || status == .authorizedAlways
        #else
        let authorized = status == .authorizedWhenInUse || status == .authorizedAlways
        #endif
        guard authorized else { throw CLError(.denied) }

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            continuations.append(continuation)
            lock.unlock()
            DispatchQueue.main.async {
                self.manager.requestLocation()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.resumeAll(with: .failure(CLError(.locationUnknown)))
            }
        }
    }

    private func resumeAll(with result: Result<CLLocation, Error>) {
        lock.lock()
        let pending = continuations
        continuations.removeAll()
        lock.unlock()
        for continuation in pending {
            switch result {
            case .success(let location): continuation.resume(returning: location)
            case .failure(let error): continuation.resume(throwing: error)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        resumeAll(with: .success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        resumeAll(with: .failure(error))
    }
}
