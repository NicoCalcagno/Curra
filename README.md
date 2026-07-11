# Curra

Personal running app for iPhone + Apple Watch: activity history (Strava + HealthKit),
custom goals, instant workouts and training plans delivered to the Watch via WorkoutKit,
personal heatmap, route builder with offline maps.

Single user, no backend, no account: all data stays on device (SwiftData + HealthKit).
The only external calls are the Strava API and (later) routing/tile providers.

- High-level plan: `PIANO_IMPLEMENTATIVO.md` (provided by the owner)
- Detailed plan: [`docs/DETAILED_IMPLEMENTATION_PLAN.md`](docs/DETAILED_IMPLEMENTATION_PLAN.md)

## Requirements

- Xcode 16+ (iOS 17 SDK), iPhone on iOS 17+, Apple Watch on watchOS 10+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
  (build-time tool only; no third-party code is linked into the app)
- Optional: [SwiftLint](https://github.com/realm/SwiftLint)

## Getting started

```bash
xcodegen generate     # creates Curra.xcodeproj from project.yml
open Curra.xcodeproj
```

1. In *Signing & Capabilities* select your team (set `DEVELOPMENT_TEAM` in `project.yml`
   to persist it). Without a paid Apple Developer account the app must be re-installed
   from Xcode every 7 days.
2. Build & run on the physical iPhone (HealthKit/WorkoutKit are unreliable on Simulator).
3. On first launch grant HealthKit read access when prompted.

### Strava setup (one-time)

1. Create an API application at <https://www.strava.com/settings/api>
   (Authorization Callback Domain: `localhost`).
2. In Curra → Settings → Strava, enter the Client ID and Client Secret, then
   *Connect Strava* and run the historical import.

## Testing

Unit tests cover the pure logic (dedup, goals, workout generation, polyline codec):

```bash
xcodebuild test -scheme Curra -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

### Manual on-device checklist (not automatable)

- [ ] HealthKit permission prompt appears and reading works
- [ ] A new run recorded on the Watch appears in Curra without manual action
- [ ] Strava full import completes without duplicates (Watch runs uploaded to Strava are merged)
- [ ] A generated workout appears in the Watch Workout app and pace alerts fire
- [ ] The weekly-goal widget updates after a run

## Status

| Phase | Scope | Status |
|---|---|---|
| 0 | Project scaffold | done |
| 1 | Data layer, Strava + HealthKit import, dedup | done (device validation pending) |
| 2 | Custom goals + widget | done (device validation pending) |
| 3 | Instant workouts → Watch | done (device validation pending) |
| 4 | Training plans | done (device validation pending) |
| 5 | Heatmap | done (device validation pending) |
| 6 | Route builder / suggested routes (OpenRouteService) | done (device validation pending) |
| 7 | Offline maps (OpenFreeMap + MapLibre) | done (device validation pending) |

### Routing setup (one-time, for the route builder)

Create a free account at <https://openrouteservice.org>, request an API token,
and paste it in Curra → Settings → Routing.

> This codebase was authored without access to Xcode; APIs follow the documented iOS 17
> SDK but the first build on a Mac may need small fixes, most likely confined to
> `Engines/Workouts/WorkoutKitBuilder.swift`, `WorkoutSchedulerService.swift`,
> `Services/OfflineMaps/OfflineMapService.swift`, and `RouteLibreMapView.swift`
> (WorkoutKit and MapLibre surface areas).
