# SpaceBuddy

A SwiftUI + RealityKit component that renders a 3-D Earth horizon view for a satellite tracker, matching Apple's *Satellite Connection* UI style.

---

## Files

| File | Description |
|------|-------------|
| `SpaceBuddy/EarthHorizonView.swift` | Full-screen SwiftUI view with the 3-D Earth scene |
| `SpaceBuddy/EarthCoordinate.swift` | `EarthCoordinate` value type + lat/lon → Cartesian math |

---

## Requirements

- **iOS 18.0+** (uses `RealityView` and `PerspectiveCameraComponent`)
- **RealityKit** framework linked in your target
- An Xcode project / Swift Package with the two source files added

---

## Asset setup

1. In your Xcode project open **Assets.xcassets**.
2. Import a NASA Blue Marble day-map (recommended: 8 192 × 4 096 px).  
   Free source: <https://visibleearth.nasa.gov/images/57730>
3. Name the asset **`earth_daymap`**.

If the texture is missing the Earth falls back to a deep-ocean blue tint so the scene still renders.

---

## Usage

```swift
import SwiftUI

struct ContentView: View {
    @State private var markerCoord = EarthCoordinate(latitude: -33.87, longitude: 151.21)

    var body: some View {
        EarthHorizonView(markerCoordinate: markerCoord)
            .ignoresSafeArea()
    }
}
```

To move the satellite marker, update `markerCoordinate`; the `RealityView` update closure repositions the entity without rebuilding the scene.

---

## Scene overview

| Feature | Implementation |
|---------|---------------|
| Earth sphere | `ModelEntity` + `PhysicallyBasedMaterial` (roughness 0.85, metallic 0.02) |
| NASA texture | `TextureResource(named: "earth_daymap")` applied to PBR `baseColor` |
| Terminator line | `DirectionalLightComponent` (9 000 lux) aimed from upper-right |
| Atmosphere glow | Slightly larger sphere with `UnlitMaterial` + additive blending + `OpacityComponent(opacity: 0.20)` |
| Camera | `PerspectiveCameraComponent` (FOV 55°) at altitude +0.45, pitched −12° so the curved horizon sits in the lower half of the screen |
| Satellite marker | White dot + flat ring `ModelEntity`; position updated via `EarthCoordinate.toCartesian(radius:)` |