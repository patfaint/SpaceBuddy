import Foundation
import RealityKit

/// A geographic coordinate used to place entities on the Earth sphere.
public struct EarthCoordinate: Equatable, Sendable {
    /// Degrees north of the equator (−90 … +90).
    public var latitude: Double
    /// Degrees east of the prime meridian (−180 … +180).
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude  = latitude
        self.longitude = longitude
    }

    // MARK: - Coordinate conversion

    /// Returns the 3-D Cartesian position for this coordinate on a sphere of the given radius.
    ///
    /// **RealityKit coordinate frame** — Y-up, right-handed:
    /// - The prime meridian (lon = 0°) maps onto **+Z**.
    /// - East longitude maps onto **+X**.
    /// - North latitude maps onto **+Y**.
    ///
    /// - Parameter radius: Distance from the origin in scene units.
    public func toCartesian(radius: Float) -> SIMD3<Float> {
        let φ = Float(latitude  * .pi / 180)   // polar angle from equator
        let λ = Float(longitude * .pi / 180)   // azimuth around Y-axis
        return SIMD3<Float>(
            radius * cos(φ) * sin(λ),   // X → east
            radius * sin(φ),            // Y → north
            radius * cos(φ) * cos(λ)    // Z → prime meridian
        )
    }
}
