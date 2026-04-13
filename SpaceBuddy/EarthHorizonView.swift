import SwiftUI
import RealityKit

/// A full-screen SwiftUI view that renders a 3-D Earth using RealityKit,
/// styled to match Apple's *Satellite Connection* horizon UI.
///
/// ## Asset setup
/// Add a NASA Blue Marble day-map image to your asset catalogue with the
/// name **"earth_daymap"**.  A free 8 192 × 4 096 px source is available at:
/// https://visibleearth.nasa.gov/images/57730
///
/// ## Usage
/// ```swift
/// EarthHorizonView(markerCoordinate: EarthCoordinate(latitude: -33.87,
///                                                    longitude: 151.21))
/// ```
@available(iOS 18.0, *)
public struct EarthHorizonView: View {

    // MARK: - Public interface

    /// Current geographic position of the satellite marker.
    /// Changing this value causes the marker to move without rebuilding the scene.
    public var markerCoordinate: EarthCoordinate

    public init(
        markerCoordinate: EarthCoordinate = EarthCoordinate(
            latitude: -33.8688,
            longitude: 151.2093
        )
    ) {
        self.markerCoordinate = markerCoordinate
    }

    // MARK: - View

    public var body: some View {
        ZStack {
            // Pure-black background fills any gap between view edges and
            // the RealityKit content, giving the appearance of deep space.
            Color.black.ignoresSafeArea()

            RealityView { content in
                // Build the full entity tree, then add the root synchronously.
                // The scene-building is kept separate to avoid capturing the
                // inout `content` parameter across suspension points.
                let root = Self.buildScene()
                content.add(root)
            } update: { content in
                // Reposition the marker whenever markerCoordinate changes.
                guard
                    let root      = content.entities.first,
                    let earth     = root.findEntity(named: "Earth"),
                    let marker    = earth.findEntity(named: "SatelliteMarker")
                else { return }

                marker.position = markerCoordinate.toCartesian(
                    radius: Self.earthRadius + Self.markerAltitude
                )
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Scene constants

    private static let earthRadius:    Float = 6.0
    private static let markerAltitude: Float = 0.14

    // MARK: - Scene assembly

    @MainActor
    private static func buildScene(in content: inout RealityViewContent) async {
        let root = Entity()

        // 1. Earth sphere
        let earth = await makeEarth(radius: earthRadius)
        earth.name = "Earth"

        // 3. Atmosphere shell (child of Earth so it rotates with it)
        let atmosphere = makeAtmosphere(radius: earthRadius * 1.024)
        atmosphere.name = "Atmosphere"
        earth.addChild(atmosphere)

        // 5. Satellite marker (default position: Sydney, Australia)
        let marker = makeSatelliteMarker(
            earthRadius: earthRadius,
            coordinate: EarthCoordinate(latitude: -33.8688, longitude: 151.2093)
        )
        marker.name = "SatelliteMarker"
        earth.addChild(marker)

        // 2. Directional sun light → natural terminator (day/night line)
        let sun = makeSunLight()

        // 4. Perspective camera just above the surface
        let camera = makeCamera(earthRadius: earthRadius)

        root.addChild(earth)
        root.addChild(sun)
        root.addChild(camera)
        content.add(root)
    }

    // MARK: - Requirement 1 · Earth entity

    /// Creates a PBR `ModelEntity` sphere textured with the NASA day-map.
    ///
    /// - **Roughness 0.85** – diffuse, matte look (no plastic highlights).
    /// - **Metallic 0.02** – almost no metallic sheen.
    private static func makeEarth(radius: Float) async -> ModelEntity {
        var pbr = PhysicallyBasedMaterial()

        // Load the NASA day-map from the asset catalogue; fall back to a
        // deep-ocean tint when the texture is absent.
        if let texture = try? await TextureResource(named: "earth_daymap") {
            pbr.baseColor = .init(texture: .init(texture))
        } else {
            pbr.baseColor = .init(
                tint: UIColor(red: 0.05, green: 0.15, blue: 0.38, alpha: 1)
            )
        }

        pbr.roughness = .init(floatLiteral: 0.85)
        pbr.metallic  = .init(floatLiteral: 0.02)

        return ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [pbr]
        )
    }

    // MARK: - Requirement 3 · Atmosphere

    /// Creates a slightly-larger, translucent sphere that simulates atmospheric
    /// scattering.  Additive blending makes it brighter at the limb where more
    /// atmosphere is integrated along the line of sight.
    private static func makeAtmosphere(radius: Float) -> ModelEntity {
        var mat = UnlitMaterial()
        // Soft sky-blue; opacity is controlled by the blending mode below.
        mat.color    = .init(
            tint: UIColor(red: 0.30, green: 0.62, blue: 1.00, alpha: 1.0)
        )
        // Additive blending → glows brightest where it overlaps itself at the
        // edge of the sphere, producing the characteristic horizon halo.
        mat.blending = .add

        let entity = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [mat]
        )

        // Scale down the contribution so it reads as a subtle glow rather than
        // an opaque shell.  OpacityComponent multiplies the rendered alpha.
        entity.components.set(OpacityComponent(opacity: 0.20))
        return entity
    }

    // MARK: - Requirement 5 · Satellite marker

    /// Creates the satellite marker: a white dot with a semi-transparent outer
    /// ring, positioned above the Earth's surface at the given coordinate.
    private static func makeSatelliteMarker(
        earthRadius: Float,
        coordinate: EarthCoordinate
    ) -> Entity {
        let root = Entity()

        // --- Inner white dot ---
        var fill = UnlitMaterial()
        fill.color = .init(tint: .white)
        let dot = ModelEntity(
            mesh: .generateSphere(radius: 0.055),
            materials: [fill]
        )
        root.addChild(dot)

        // --- Outer ring (flat, thin cylinder standing vertically) ---
        // A very flat cylinder gives a disc; together with the dot it mimics
        // the circular marker in Apple's Satellite Connection UI.
        var ringMat = UnlitMaterial()
        ringMat.color    = .init(tint: UIColor.white.withAlphaComponent(0.75))
        ringMat.blending = .transparent(opacity: .init(floatLiteral: 0.75))
        let ring = ModelEntity(
            mesh: .generateCylinder(height: 0.006, radius: 0.09),
            materials: [ringMat]
        )
        root.addChild(ring)

        // Place the marker on the sphere surface.
        root.position = coordinate.toCartesian(radius: earthRadius + markerAltitude)
        return root
    }

    // MARK: - Requirement 2 · Sun / directional light

    /// Creates a directional light positioned to the upper-right of Earth,
    /// producing a realistic day/night terminator line on the PBR sphere.
    private static func makeSunLight() -> Entity {
        let entity = Entity()

        var light = DirectionalLightComponent()
        light.color     = .init(white: 1.0, alpha: 1.0)
        // High intensity is needed to overcome the IBL baseline and produce
        // a strong terminator with a clean shadow transition.
        light.intensity = 9_000
        entity.components.set(light)

        // Aim the sun from upper-right so the terminator falls across the
        // visible hemisphere in a visually interesting way.
        entity.look(
            at: .zero,
            from: SIMD3<Float>(8, 4, 6),
            relativeTo: nil
        )
        return entity
    }

    // MARK: - Requirement 4 · Perspective camera

    /// Creates a perspective camera positioned just above the Earth's surface.
    ///
    /// - FOV 55° gives a moderate "orbital" feel without excessive distortion.
    /// - The camera is placed directly above the origin (+Y) with a small +Z
    ///   offset and then pitched down 12°, which pushes the curved horizon into
    ///   the lower half of the screen and leaves deep space at the top.
    private static func makeCamera(earthRadius: Float) -> Entity {
        let entity = Entity()

        var cam = PerspectiveCameraComponent()
        cam.near                 = 0.01
        cam.far                  = 500.0
        cam.fieldOfViewInDegrees = 55.0
        entity.components.set(cam)

        // ~7 % above the surface — close enough to see strong curvature.
        let altitude: Float = earthRadius + 0.45
        // Small +Z offset so Earth fills the lower frame rather than centring.
        entity.position = SIMD3<Float>(0, altitude, 0.35)

        // Pitch forward (nose down) so the horizon arc sits in the lower half.
        entity.orientation = simd_quatf(
            angle: Float(-12 * .pi / 180),
            axis:  SIMD3<Float>(1, 0, 0)
        )
        return entity
    }
}

// MARK: - Preview

@available(iOS 18.0, *)
#Preview {
    EarthHorizonView(
        markerCoordinate: EarthCoordinate(latitude: -33.8688, longitude: 151.2093)
    )
}
