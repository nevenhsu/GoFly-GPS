import Foundation
import GoFlyCore

/// Keeps the fly origin across launches, so Stop after a relaunch still
/// returns there before clearing. A confirmed clear removes it.
struct GoFlyFlyOriginStore {
    private static let key = "GoFly.flyOrigin"
    let enabled: Bool
    var defaults: UserDefaults = .standard

    func load() -> GeoCoordinate? {
        guard enabled, let values = defaults.array(forKey: Self.key) as? [Double], values.count == 2 else { return nil }
        return GeoCoordinate(latitude: values[0], longitude: values[1])
    }

    func save(_ origin: GeoCoordinate?) {
        guard enabled else { return }
        if let origin {
            defaults.set([origin.latitude, origin.longitude], forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }
}
