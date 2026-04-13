import SwiftUI
import RealityKit
import CoreImage

/// A full-screen SwiftUI view that renders a 3-D Earth using RealityKit,
/// styled to match Apple's *Satellite Connection* horizon UI.
///
/// ## Required assets (add to Assets.xcassets)
///
/// All textures are available from
/// [Solar System Scope — Textures](https://www.solarsystemscope.com/textures/)
/// under a CC BY 4.0 licence (credit: Solar System Scope / INOVE).
///
/// | Name | Description | Solar System Scope file |
/// |------|-------------|------------------------|
/// | `earth_daymap` | Day colour map (8 192 × 4 096 px) | `8k_earth_daymap.jpg` |
/// | `earth_nightmap` | City-lights map (8 192 × 4 096 px) | `8k_earth_nightmap.jpg` |
/// | `earth_normal` | Terrain normal map (8 192 × 4 096 px) | `8k_earth_normal_map.tif` |
/// | `earth_roughness` **or** `earth_specular` | Ocean/land roughness mask (8 192 × 4 096 px) | `8k_earth_specular_map.tif` |
/// | `earth_clouds` | Cloud cover opacity mask (8 192 × 4 096 px) | `8k_earth_clouds.jpg` |
///
/// > **Specular → roughness:** You can add the Solar System Scope specular
/// > map directly as `earth_specular` — the code inverts it automatically at
/// > load time. Alternatively, if you prefer to pre-invert the image yourself,
/// > name the result `earth_roughness` and it will be used as-is.
///
/// All textures fall back gracefully so the scene renders even without assets.
///
/// ## Usage
/// ```swift
/// EarthHorizonView(markerCoordinate: EarthCoordinate(latitude: -33.87,
///                                                    longitude: 151.21))
/// ```
@available(iOS 26.0, *)
public struct EarthHorizonView: View {

    // MARK: - Public interface

    /// Geographic position of the satellite marker.
    /// Update this value to reposition the marker without rebuilding the scene.
    public var markerCoordinate: EarthCoordinate

    public init(
        markerCoordinate: EarthCoordinate = EarthCoordinate(
            latitude: -33.8688,
            longitude: 151.2093   // Default: Sydney, Australia
        )
    ) {
        self.markerCoordinate = markerCoordinate
    }

    // MARK: - View

    public var body: some View {
        ZStack {
            // Black background = deep space behind the RealityKit content.
            Color.black.ignoresSafeArea()

            RealityView { content in
                // All async texture loading happens inside makeRoot().
                // The inout `content` is only touched after every suspension
                // point has resolved, so Swift's ownership rules are satisfied.
                let root = await Self.makeRoot()
                content.add(root)
            } update: { content in
                // RealityView calls this closure whenever the parent SwiftUI
                // state causes EarthHorizonView to be re-evaluated (i.e. when
                // markerCoordinate changes).  Only the marker position is
                // mutated — the rest of the scene is left untouched.
                guard
                    let root   = content.entities.first,
                    let earth  = root.findEntity(named: "Earth"),
                    let marker = earth.findEntity(named: "SatelliteMarker")
                else { return }

                marker.position = markerCoordinate.toCartesian(
                    radius: Self.earthRadius + Self.markerAltitude
                )
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Scene constants

    /// Radius of the Earth sphere in scene units.
    private static let earthRadius:    Float = 6.0
    /// How far above the surface the satellite marker floats.
    private static let markerAltitude: Float = 0.14

    // MARK: - Scene root

    /// Builds the complete entity hierarchy and returns the root.
    ///
    /// Texture loads are performed here so no `inout RealityViewContent`
    /// parameter is captured across Swift concurrency suspension points.
    @MainActor
    private static func makeRoot() async -> Entity {
        let root = Entity()

        // ── Earth ─────────────────────────────────────────────────────────
        let earth = await makeEarth(radius: earthRadius)
        earth.name = "Earth"

        // ── Atmosphere (child of Earth – rotates with the globe) ──────────
        // Outer halo: wide, very transparent rim glow.
        let outerAtmo = makeAtmosphereShell(
            radius: earthRadius * 1.045,
            color:  UIColor(red: 0.20, green: 0.55, blue: 1.00, alpha: 1),
            opacity: 0.10
        )
        outerAtmo.name = "AtmosphereOuter"
        earth.addChild(outerAtmo)

        // Inner scattering shell: tighter, slightly more opaque blue.
        let innerAtmo = makeAtmosphereShell(
            radius: earthRadius * 1.018,
            color:  UIColor(red: 0.35, green: 0.68, blue: 1.00, alpha: 1),
            opacity: 0.18
        )
        innerAtmo.name = "AtmosphereInner"
        earth.addChild(innerAtmo)

        // ── Cloud layer ────────────────────────────────────────────────────
        let clouds = await makeClouds(radius: earthRadius * 1.010)
        clouds.name = "Clouds"
        earth.addChild(clouds)

        // ── Satellite marker ───────────────────────────────────────────────
        let marker = makeSatelliteMarker(
            earthRadius: earthRadius,
            coordinate: EarthCoordinate(latitude: -33.8688, longitude: 151.2093)
        )
        marker.name = "SatelliteMarker"
        earth.addChild(marker)

        // ── Lighting ───────────────────────────────────────────────────────
        // Primary: strong sun for a crisp terminator line.
        let sun = makeSun()
        // Secondary: faint blue-grey fill simulating reflected moonlight,
        // so the night-side geography is barely discernible (not black void).
        let moonlight = makeMoonlight()

        // ── Camera ────────────────────────────────────────────────────────
        let camera = makeCamera(earthRadius: earthRadius)

        root.addChild(earth)
        root.addChild(sun)
        root.addChild(moonlight)
        root.addChild(camera)
        return root
    }

    // MARK: - Texture helpers

    /// Loads a texture from the asset catalogue and inverts (negates) its
    /// colour values using Core Image, so a specular map (bright = shiny)
    /// becomes a roughness map (bright = rough).
    private static func loadInvertedTexture(named name: String) async -> TextureResource? {
        guard let uiImage = UIImage(named: name),
              let ciInput = CIImage(image: uiImage) else { return nil }

        let inverted = ciInput.applyingFilter("CIColorInvert")
        let context = CIContext()
        guard let cgImage = context.createCGImage(inverted, from: inverted.extent) else { return nil }

        return try? await TextureResource.generate(from: cgImage, options: .init(semantic: .raw))
    }

    // MARK: - Earth (Req 1)

    /// Creates a PBR sphere representing Earth.
    ///
    /// Texture usage:
    /// - **baseColor**      ← `earth_daymap`   (NASA Blue Marble)
    /// - **normal**         ← `earth_normal`   (terrain relief)
    /// - **roughness**      ← `earth_roughness` (dark = smooth ocean, bright = rough land)
    /// - **emissiveColor**  ← `earth_nightmap` (NASA Black Marble city lights)
    ///
    /// The emissive city-lights are permanently active, but the 10 000 lux
    /// directional sun completely overwhelms them on the day side, so they
    /// only become visible in the PBR shadow — giving a natural terminator.
    private static func makeEarth(radius: Float) async -> ModelEntity {
        var pbr = PhysicallyBasedMaterial()

        // ── Day colour ────────────────────────────────────────────────────
        if let tex = try? await TextureResource(named: "earth_daymap") {
            pbr.baseColor = .init(texture: .init(tex))
        } else {
            pbr.baseColor = .init(
                tint: UIColor(red: 0.05, green: 0.15, blue: 0.38, alpha: 1)
            )
        }

        // ── Terrain normal map ────────────────────────────────────────────
        if let tex = try? await TextureResource(named: "earth_normal") {
            pbr.normal = .init(texture: .init(tex))
        }

        // ── Roughness: ocean (dark/smooth) vs land (bright/rough) ─────────
        // Accepts either a pre-inverted roughness map (`earth_roughness`) or
        // the original specular map (`earth_specular`) which is negated at
        // load time so bright → rough and dark → smooth.
        if let tex = try? await TextureResource(named: "earth_roughness") {
            pbr.roughness = .init(texture: .init(tex))
        } else if let tex = await Self.loadInvertedTexture(named: "earth_specular") {
            pbr.roughness = .init(texture: .init(tex))
        } else {
            pbr.roughness = .init(floatLiteral: 0.75)
        }

        // Low metallic — Earth is not metallic; near-zero prevents plastic sheen.
        pbr.metallic = .init(floatLiteral: 0.02)

        // ── City lights (emissive) ─────────────────────────────────────────
        // Visible only on the dark side because sunlight overpowers them
        // during the day (no custom shader required).
        if let tex = try? await TextureResource(named: "earth_nightmap") {
            pbr.emissiveColor     = .init(texture: .init(tex))
            pbr.emissiveIntensity = 0.7
        }

        return ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [pbr]
        )
    }

    // MARK: - Cloud layer

    /// A semi-transparent sphere slightly above the surface carrying the
    /// NASA cloud-cover mask.  When the texture is present it replaces the
    /// white base colour; the `blending` value keeps the layer translucent.
    private static func makeClouds(radius: Float) async -> ModelEntity {
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: UIColor(white: 1, alpha: 1))
        mat.roughness = .init(floatLiteral: 0.95)
        mat.metallic  = .init(floatLiteral: 0.00)

        if let tex = try? await TextureResource(named: "earth_clouds") {
            // Cloud mask: white = cloud, black = clear sky.
            mat.baseColor = .init(texture: .init(tex))
        }
        // Even without a texture, a lightly transparent shell is visible.
        mat.blending = .transparent(opacity: .init(floatLiteral: 0.82))

        return ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [mat]
        )
    }

    // MARK: - Atmosphere (Req 3)

    /// Creates a single atmospheric shell.
    ///
    /// Two shells are stacked (outer halo + inner scattering) to reproduce
    /// the soft blue limb glow visible in the reference screenshot.
    /// `UnlitMaterial` with transparent blending is used so the atmosphere
    /// glows independently of the directional sun — physically this
    /// corresponds to Rayleigh scattering which is view-angle-dependent.
    private static func makeAtmosphereShell(
        radius:  Float,
        color:   UIColor,
        opacity: Float
    ) -> ModelEntity {
        var mat = UnlitMaterial()
        mat.color    = .init(tint: color)
        // Transparent blending lets the shell accumulate along the limb where
        // many layers of atmosphere overlap, creating the characteristic bright
        // ring.  OpacityComponent (set below) controls the final rendered alpha.
        mat.blending = .transparent(opacity: .init(floatLiteral: 1.0))

        let entity = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [mat]
        )
        // OpacityComponent multiplies the final rendered alpha so the
        // additive-like contribution stays subtle rather than washing out the scene.
        entity.components.set(OpacityComponent(opacity: opacity))
        return entity
    }

    // MARK: - Satellite marker (Req 5)

    /// A white dot + translucent ring entity, matching the circular marker
    /// in Apple's Satellite Connection UI.
    ///
    /// Use `EarthCoordinate.toCartesian(radius:)` to reposition at runtime.
    private static func makeSatelliteMarker(
        earthRadius: Float,
        coordinate:  EarthCoordinate
    ) -> Entity {
        let root = Entity()

        // ── Filled white dot ──────────────────────────────────────────────
        var dotMat = UnlitMaterial()
        dotMat.color = .init(tint: .white)
        let dot = ModelEntity(
            mesh: .generateSphere(radius: 0.055),
            materials: [dotMat]
        )
        root.addChild(dot)

        // ── Outer ring: flat cylinder acts as a disc ───────────────────────
        // Height 0.006 gives a near-invisible thickness; radius 0.095 creates
        // the enclosing circle visible in the reference screenshot.
        var ringMat = UnlitMaterial()
        ringMat.color    = .init(tint: UIColor.white.withAlphaComponent(0.75))
        ringMat.blending = .transparent(opacity: .init(floatLiteral: 0.75))
        let ring = ModelEntity(
            mesh: .generateCylinder(height: 0.006, radius: 0.095),
            materials: [ringMat]
        )
        root.addChild(ring)

        root.position = coordinate.toCartesian(radius: earthRadius + markerAltitude)
        return root
    }

    // MARK: - Sun / directional light (Req 2)

    /// Strong directional light that produces the day/night terminator line.
    ///
    /// At 10 000 lux the PBR Earth transitions sharply from lit to unlit,
    /// creating a clean terminator.  Shadow casting is enabled to allow
    /// the cloud layer to cast shadows onto the surface.
    private static func makeSun() -> Entity {
        let entity = Entity()

        var light = DirectionalLightComponent()
        light.color     = UIColor(red: 1.00, green: 0.97, blue: 0.90, alpha: 1) // warm white
        light.intensity = 10_000

        // Shadow from the sun lets the cloud layer cast subtle shadows and
        // ensures the night side is properly dark without a fill-light leak.
        var shadow = DirectionalLightComponent.Shadow()
        shadow.shadowProjection = .automatic(maximumDistance: 25)
        shadow.depthBias        = 2.0
        entity.components.set(shadow)

        entity.components.set(light)

        // Sun is upper-right so the terminator falls across the scene
        // in a visually interesting diagonal.
        entity.look(at: .zero, from: SIMD3<Float>(8, 4, 6), relativeTo: nil)
        return entity
    }

    // MARK: - Moonlight fill

    /// Very dim, cool-blue point light on the night side to prevent the
    /// dark hemisphere from being an absolute void and to faintly reveal
    /// ocean / continent shapes — simulating Earthshine / moonlight.
    private static func makeMoonlight() -> Entity {
        let entity = Entity()

        var light = PointLightComponent()
        light.color             = UIColor(red: 0.55, green: 0.65, blue: 0.85, alpha: 1)
        light.intensity         = 120            // extremely faint
        light.attenuationRadius = 30

        entity.components.set(light)
        // Opposite side of the Earth from the sun.
        entity.position = SIMD3<Float>(-8, -4, -6)
        return entity
    }

    // MARK: - Perspective camera (Req 4)

    /// Positions the camera just above the Earth's surface so the curved
    /// horizon sits in the lower half of the screen with deep space above.
    ///
    /// - **FOV 55°** gives a moderate "orbital" field of view — wide enough
    ///   to show strong curvature, not so wide as to cause fisheye distortion.
    /// - Camera sits ~7 % of Earth-radius above the surface (+0.45 units).
    /// - A small forward (+Z) offset pushes the Earth below screen centre.
    /// - A −12° pitch (nose down) brings the horizon arc into the lower half.
    private static func makeCamera(earthRadius: Float) -> Entity {
        let entity = Entity()

        var cam = PerspectiveCameraComponent()
        cam.near                 = 0.01
        cam.far                  = 500.0
        cam.fieldOfViewInDegrees = 55.0
        entity.components.set(cam)

        entity.position = SIMD3<Float>(0, earthRadius + 0.45, 0.35)
        entity.orientation = simd_quatf(
            angle: -12.0 * Float.pi / 180.0,
            axis:  SIMD3<Float>(1, 0, 0)
        )
        return entity
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    EarthHorizonView(
        markerCoordinate: EarthCoordinate(latitude: -33.8688, longitude: 151.2093)
    )
}
