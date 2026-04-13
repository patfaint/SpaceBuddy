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

- **iOS 26.0+** / **Xcode 26+** (uses `RealityView`, `PerspectiveCameraComponent`, `OpacityComponent`)
- **RealityKit** framework linked in your target

---

## Asset setup

Add the following images to **Assets.xcassets** with exactly these names:

| Asset name | Description | Recommended size | Free source |
|------------|-------------|-----------------|-------------|
| `earth_daymap` | NASA Blue Marble colour map | 8 192 × 4 096 px | [visibleearth.nasa.gov/images/57730](https://visibleearth.nasa.gov/images/57730) |
| `earth_nightmap` | NASA Black Marble city lights | 8 192 × 4 096 px | [visibleearth.nasa.gov/images/55167](https://visibleearth.nasa.gov/images/55167) |
| `earth_normal` | Terrain normal map | 4 096 × 2 048 px | [visibleearth.nasa.gov/images/73934](https://visibleearth.nasa.gov/images/73934) |
| `earth_roughness` | Ocean/land roughness mask — dark (smooth ocean) / bright (rough land) | 4 096 × 2 048 px | [visibleearth.nasa.gov/images/73963](https://visibleearth.nasa.gov/images/73963) |
| `earth_clouds` | Cloud cover opacity mask | 4 096 × 2 048 px | [visibleearth.nasa.gov/images/57747](https://visibleearth.nasa.gov/images/57747) |

All textures have graceful fallbacks so the scene renders even when assets are absent.

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
| **Earth sphere** | `ModelEntity` + `PhysicallyBasedMaterial` |
| **Day colour** | `earth_daymap` → PBR `baseColor` |
| **Terrain relief** | `earth_normal` → PBR `normal` |
| **Ocean reflectivity** | `earth_roughness` → PBR `roughness` (dark = smooth ocean, bright = matte land) |
| **City lights** | `earth_nightmap` → PBR `emissiveColor`; 10 000 lux sun overpowers emissive on day side so lights appear only in darkness — no shader needed |
| **Cloud layer** | Separate sphere at 1.01× radius; `earth_clouds` greyscale mask drives PBR `opacity` |
| **Atmosphere glow** | Two-shell `UnlitMaterial` + additive blending + `OpacityComponent`; limb brightness accumulates at the edges naturally |
| **Terminator line** | `DirectionalLightComponent` (10 000 lux, warm white) with shadow enabled |
| **Night-side fill** | `PointLightComponent` (120 lux, cool blue) on the opposite side — simulates moonlight/earthshine |
| **Camera** | `PerspectiveCameraComponent` FOV 55°, altitude +0.45, pitch −12° so the curved horizon sits in the lower half |
| **Satellite marker** | White dot + flat ring; position driven by `EarthCoordinate.toCartesian(radius:)` |