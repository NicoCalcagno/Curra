# Curra — Detailed Implementation Plan

> Deep-dive companion to `PIANO_IMPLEMENTATIVO.md` (high-level plan). This document specifies
> every module, model, algorithm, API interaction, file, and test needed to build the app.
> Code, commits, and docs are in English. All non-negotiable constraints from the high-level
> plan apply verbatim (single user, no backend, no Garmin, no live tracking, on-device data).

---

## 0. Ground rules and environment reality

- **Target**: iOS 17+, Swift 6, SwiftUI. iPhone 14 Pro Max + Apple Watch Series 9 (watchOS 10+).
- **No dedicated watchOS app**: workouts reach the Watch via WorkoutKit scheduling into the
  native Workout app.
- **Xcode project generation**: the repository ships a `project.yml` for **XcodeGen**
  (`brew install xcodegen && xcodegen generate`). XcodeGen is a *build-time developer tool*,
  not a runtime dependency — no third-party code is linked into the app. If you prefer not to
  use it, create an empty Xcode app project manually and drag the `Curra/`, `CurraWidget/`
  and `CurraTests/` folders in; `project.yml` documents every capability/plist key needed.
- **What cannot be verified off-device**: HealthKit, WorkoutKit and widgets are unreliable or
  unavailable on the Simulator. Acceptance criteria for Phases 1, 3, 4 are verified **only on
  the physical iPhone + Watch**. Pure-logic engines (dedup, goals, workout generation,
  polyline) are covered by unit tests that run anywhere Xcode runs.
- **Signing**: without the Apple Developer Program the app must be re-signed every 7 days from
  Xcode (free provisioning). This blocks nothing in the codebase; decide before daily use.

---

## 1. Repository layout

```
project.yml                      # XcodeGen manifest (targets, capabilities, plist)
.swiftlint.yml
.gitignore
README.md
docs/
  DETAILED_IMPLEMENTATION_PLAN.md
Curra/                           # iOS app target
  App/                           # entry point, root navigation, DI
  Support/                       # entitlements (generated Info.plist via project.yml)
  Models/                        # SwiftData @Model classes + shared value types
  Services/
    HealthKit/                   # HealthKitService (queries, observer, route loading)
    Strava/                      # OAuth, API client, rate limiter, keychain, importer
    Sync/                        # ActivitySyncCoordinator (orchestration + dedup + persistence)
  Engines/                       # pure logic, no framework deps where possible
    Dedup/
    Goals/
    Workouts/                    # blueprint types, generator, WorkoutKit mapping, scheduler
  Features/                      # SwiftUI screens grouped by feature
    Dashboard/
    Activities/
    Workouts/
    Settings/
  Shared/                        # app-group snapshot types shared with the widget
  Utilities/                     # polyline codec, formatters
CurraWidget/                     # WidgetKit extension (weekly goal progress)
CurraTests/                      # XCTest unit tests (pure logic only)
```

**Design rule**: everything that contains decision logic (dedup, goal math, workout
generation, plan generation later) is implemented as **pure functions over value types**
(`ActivitySummary`, `WorkoutBlueprint`, …), with SwiftData/HealthKit/WorkoutKit kept in thin
adapter layers. This is what makes the logic unit-testable without a device.

---

## 2. Architecture

### 2.1 Concurrency model (Swift 6, strict concurrency)

- SwiftData `ModelContainer` is created once in `CurraApp`; UI reads via `@Query`.
- Writes go through `@MainActor` coordinators (`ActivitySyncCoordinator`) — for a single-user
  personal dataset (<10k activities) main-actor writes are fine; no background ModelContext
  gymnastics in v1.
- Network and HealthKit callbacks hop to the main actor before touching the context.
- `StravaRateLimiter` is an `actor` (shared mutable counters).

### 2.2 Data flow

```
Strava (one-shot historical import + manual re-sync)
        ─┐
         ├─→ [ActivitySummary] ─→ DeduplicationEngine ─→ SwiftData Activity
        ─┘                                                    │
HealthKit (anchored query + observer for new Watch runs)      │
                                                              ▼
                                    GoalEngine / TrainingLoadCalculator / Heatmap / Plans
                                                              │
                                                              ▼
                                       Dashboard UI, Widget snapshot (App Group), Watch sync
```

### 2.3 Error handling

- Service errors are typed (`StravaError`, `HealthKitError`) and surfaced to the UI as
  non-blocking banners; sync is always resumable (anchors/pagination cursors persisted).
- Never delete user data on error. Imports are idempotent (dedup keys, see §4.3).

---

## 3. SwiftData schema (complete, defined in Phase 1, frozen afterwards)

Schema changes after Phase 1 require an explicit migration plan, so **all** models are defined
up front, including those used by later phases.

### 3.1 `Activity`
| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | local identity |
| `startDate` | `Date` | |
| `durationSeconds` | `Double` | moving time when available (Strava), else workout duration |
| `distanceMeters` | `Double` | |
| `elevationGainMeters` | `Double?` | |
| `averageHeartRate` | `Double?` | bpm |
| `name` | `String` | |
| `encodedPolyline` | `String?` | Google encoded polyline (Strava summary or encoded from HK route) |
| `sourceRaw` | `String` | `strava` \| `healthKit` \| `merged` |
| `stravaID` | `Int64?` | `.unique` dedup key |
| `healthKitUUID` | `String?` | `.unique` dedup key (HKWorkout UUID string) |
| `hasDetailedRoute` | `Bool` | whether polyline came from full GPS stream |

Derived (computed, not stored): pace (sec/km), formatted values.

### 3.2 `Goal`
| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | |
| `metricRaw` | `String` | `distance` \| `duration` \| `runCount` \| `elevationGain` |
| `periodRaw` | `String` | `weekly` \| `monthly` \| `yearly` |
| `targetValue` | `Double` | meters / seconds / count / meters |
| `createdAt` | `Date` | |
| `isActive` | `Bool` | recurring goals stay active; deactivate to archive |
| `history` | `[GoalPeriodRecord]` | relationship, cascade delete |

### 3.3 `GoalPeriodRecord` (closed-period snapshot)
`id`, `periodStart`, `periodEnd`, `achievedValue`, `targetValue`, `wasCompleted`.
Written by `GoalHistoryService` the first time a period is observed as closed.

### 3.4 `Route` (Phase 6, defined now)
`id`, `name`, `encodedPolyline`, `distanceMeters`, `elevationGainMeters`, `isFavorite`,
`createdAt`, `sourceRaw` (`manual` | `suggested`), `isOfflineAvailable` (Phase 7).

### 3.5 `TrainingPlan` (Phase 4, defined now)
`id`, `name`, `raceTypeRaw` (`fiveK` | `tenK` | `half`), `startDate`, `raceDate?`,
`isActive`, `plannedWorkouts` relationship (cascade).

### 3.6 `PlannedWorkout` (Phases 3–4, defined now)
| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | also used as `WorkoutPlan.id` for WorkoutKit correlation |
| `scheduledDate` | `Date` | |
| `blueprintData` | `Data` | JSON-encoded `WorkoutBlueprint` (value type, Codable) |
| `statusRaw` | `String` | `pending` \| `scheduledOnWatch` \| `completed` \| `skipped` |
| `matchedActivityID` | `UUID?` | adherence matching |
| `plan` | `TrainingPlan?` | nil for instant workouts that were scheduled |

**Why `blueprintData` as JSON blob**: WorkoutKit types aren't Codable/persistable and the
blueprint is a closed value type we own; storing it as JSON avoids a fragile normalized
schema for steps/blocks and survives schema freezes.

---

## 4. Phase 1 — Data layer + import (detailed)

### 4.1 Strava integration

**App setup (user, one-time)**: create an API application at strava.com/settings/api.
The app asks for *Client ID* and *Client Secret* in Settings (personal app; ID stored in
`UserDefaults`, secret in Keychain). Authorization Callback Domain: `localhost` is fine —
we use the custom scheme redirect `curra://oauth`.

**OAuth 2.0 flow** (`StravaAuthService`):
1. `ASWebAuthenticationSession` →
   `https://www.strava.com/oauth/mobile/authorize?client_id=…&redirect_uri=curra://oauth&response_type=code&approval_prompt=auto&scope=activity:read_all`
2. Callback `curra://oauth?code=…` → `POST /oauth/token` (grant_type `authorization_code`).
3. Store `access_token`, `refresh_token`, `expires_at` in Keychain (`KeychainStore`).
4. Before each API call: if `expires_at - now < 300s` → refresh (grant_type `refresh_token`).

**Historical import** (`StravaImportService`):
- `GET /api/v3/athlete/activities?per_page=200&page=N` until an empty page.
- Filter `type == "Run" || sport_type contains "Run"` (includes `TrailRun`, `VirtualRun`).
- Map to `ActivitySummary` using `moving_time`, `distance`, `total_elevation_gain`,
  `average_heartrate`, `map.summary_polyline`, `start_date` (ISO 8601 with `Z`).
- Persist a `lastImportedPage` / `after` cursor so an interrupted import resumes.
- Incremental re-sync: same endpoint with `after=<latest stored strava start ts>`.
- Detailed GPS streams (`GET /activities/{id}/streams?keys=latlng&key_by_type=true`) are
  **optional enrichment** (1 request per activity — expensive against rate limits). v1 uses
  `summary_polyline` everywhere; a per-activity "load full route" action fetches streams
  lazily and re-encodes with our polyline codec, setting `hasDetailedRoute = true`.

**Rate limiting** (`StravaRateLimiter`, actor):
- Budget: 200 requests / 15 min, 2 000 / day (read limits: 100/15min, 1000/day for
  non-upload — enforce the stricter read limits: **90/15min, 900/day** with safety margin).
- Sliding window of request timestamps; `await limiter.permit()` suspends until a slot frees.
- On HTTP 429: parse `X-RateLimit-Usage`, sleep until the next 15-minute boundary, retry
  (max 3 attempts, then surface error and persist cursor).

### 4.2 HealthKit integration (`HealthKitService`)

- **Authorization** (read-only): `HKObjectType.workoutType()`,
  `HKSeriesType.workoutRoute()`, `heartRate`, `distanceWalkingRunning`,
  `activeEnergyBurned`.
- **Initial + incremental fetch**: `HKAnchoredObjectQuery` on workouts with predicate
  `HKQuery.predicateForWorkouts(with: .running)`; the `HKQueryAnchor` is serialized
  (`NSKeyedArchiver`) into `UserDefaults` so every launch only fetches deltas.
- **Automatic sync**: `HKObserverQuery` + `enableBackgroundDelivery(for: workoutType,
  frequency: .immediate)`. The observer triggers the anchored fetch; completion handler is
  called only after persistence succeeds.
- **Route loading**: for each workout, `HKAnchoredObjectQuery` on
  `HKSeriesType.workoutRoute()` limited with `HKQuery.predicateForObjects(from: workout)`,
  then `HKWorkoutRouteQuery` streaming `[CLLocation]` batches. Locations are downsampled
  (keep 1 point every ~10 m) and encoded with the polyline codec.
- **Field mapping**: distance from `workout.statistics(for: distanceWalkingRunning)`,
  HR from `workout.statistics(for: heartRate)?.averageQuantity()`, duration from
  `workout.duration`.

### 4.3 Deduplication (`DeduplicationEngine`, pure)

Two layers:
1. **Hard keys**: `stravaID` and `healthKitUUID` are `.unique` — re-imports are no-ops.
2. **Cross-source fuzzy match** (a run recorded on the Watch also auto-uploads to Strava):
   candidate pair matches when **both**:
   - `|startDate_A − startDate_B| ≤ 300 s`
   - `|distance_A − distance_B| ≤ max(200 m, 5 % · max(distance_A, distance_B))`

   Resolution: **merge into one `Activity`** — keep the HealthKit record as the body
   (richer HR + route), attach `stravaID`, prefer the Strava name if the HK name is generic,
   set `sourceRaw = merged`. The engine is a pure function
   `merge(incoming: [ActivitySummary], existing: [ActivitySummary]) -> [MergeDecision]`
   (`insert`, `mergeInto(existingID:)`, `skip`) so it is fully unit-testable.

### 4.4 Orchestration (`ActivitySyncCoordinator`, @MainActor)

Single entry points used by UI and observer callbacks:
- `runStravaFullImport(progress:)`
- `runStravaIncrementalSync()`
- `runHealthKitSync()` (used at launch and from the observer)
Each: fetch summaries → dedup against existing → apply `MergeDecision`s → save → notify
`GoalSnapshotService` to refresh the widget snapshot.

### 4.5 Tests (Phase 1)
- `PolylineTests`: encode/decode round-trip, known Google reference vectors, precision.
- `DeduplicationEngineTests`: exact-key skip, fuzzy merge inside/outside time and distance
  windows, merge field resolution, batch with mixed decisions.
- `StravaMappingTests`: JSON fixture of `/athlete/activities` element → `ActivitySummary`
  (dates, units, run-type filtering).

**Device-only acceptance**: full activity list without duplicates; a new Watch run appears
without manual action (observer + background delivery).

---

## 5. Phase 2 — Custom Goals (detailed)

### 5.1 Period math (`GoalPeriod`)
- `weekly`: `Calendar.current.dateInterval(of: .weekOfYear, for: now)` (locale-aware week
  start — Monday for IT).
- `monthly`: `.month` interval; `yearly`: `.year` interval.
All boundaries computed in the user's current time zone at query time.

### 5.2 `GoalEngine` (pure)
```
progress(goal, activities, now) -> GoalProgress {
    periodStart, periodEnd,
    achieved   // Σ metric over activities with startDate ∈ [periodStart, periodEnd)
    target, fraction (clamped 0…1), remaining,
    paceStatus // onTrack / behind / ahead: achieved vs target · elapsedFraction
}
```
Metrics: `distance` → Σ `distanceMeters`; `duration` → Σ `durationSeconds`;
`runCount` → count; `elevationGain` → Σ elevation (nil → 0).

### 5.3 Historicization (`GoalHistoryService`)
On app foreground: for each active goal, compute the previous period's range; if no
`GoalPeriodRecord` exists for `(goal, periodStart)`, aggregate and insert one. Idempotent.

### 5.4 Widget
- `GoalSnapshot` (Codable): goal name, metric, achieved, target, fraction, period end,
  updated-at. Written as JSON to `UserDefaults(suiteName: "group.com.nicocalcagno.curra")`
  by `GoalSnapshotService` after every sync/goal edit.
- `CurraWidget` (small + medium): `TimelineProvider` reads the snapshot; one timeline entry
  now + `.after(15 min)` refresh policy. Tapping opens the app (default deep link).
- Widget reads the snapshot only — no SwiftData container in the extension (keeps the
  extension trivial and avoids container/locking issues).

### 5.5 UI
- **Dashboard**: ring per active goal (progress ring component), current week summary strip
  (km, runs, time), last activity card.
- **Goal editor**: metric picker, period picker, numeric target with unit label.
- **Goal detail**: current progress + bar chart of past periods from `GoalPeriodRecord`
  (Swift Charts).

### 5.6 Tests
`GoalEngineTests`: aggregation per metric, period boundary inclusion/exclusion (activity at
23:59 Sunday vs 00:00 Monday), empty period, over-achievement clamp, paceStatus thresholds,
historicization idempotency (pure part).

---

## 6. Phase 3 — Instant Workouts / WorkoutKit (detailed)

### 6.1 Blueprint value types (`WorkoutBlueprint`, Codable, WorkoutKit-free)
```
WorkoutBlueprint { name, mode, warmup: Step?, blocks: [Block], cooldown: Step? }
Block  { steps: [Step], iterations: Int }        // fixed iterations only (WorkoutKit limit)
Step   { purpose: work|recovery, goal: Goal, alert: Alert? }
Goal   = open | distanceMeters(Double) | durationSeconds(Double)
Alert  = heartRateZone(1…5) | paceRange(minSecPerKm, maxSecPerKm)
```
Plus computed `estimatedDistanceMeters` / `estimatedDurationSeconds` for UI (uses reference
pace where a step is time-based and vice versa).

### 6.2 Training load input (`TrainingLoadCalculator`, pure)
From the last 14 days of `Activity`:
- `weeklyKilometers` (7-day and 14-day/2 averages), `runCount7d`, `daysSinceLastRun`,
  `typicalEasyPace` = median pace of runs + 8 %, `longestRecentRunKm`,
  `estimated5KPace` = best average pace among runs ≥ 3 km − 5 % (proxy without lab data).
- Fallbacks for empty history: easy pace 6:30 /km, weekly volume 15 km, conservative
  everything.

### 6.3 Mode generators (`InstantWorkoutGenerator`, pure, deterministic given load + variant)
| Mode | Structure | Alerts |
|---|---|---|
| **Maintain** | warmup 10 min open → steady `max(30, min(60, weeklyKm·2)) min` → cooldown 5 min | HR zone 2 |
| **Build** (variants rotate) | V1: 10' wu → N×(800 m @5K pace / 400 m recovery) → 10' cd, N = clamp(weeklyKm/8, 3, 8). V2: tempo `20–35'` @ easyPace −45 s. V3: 6–10×(1' hard / 1' easy) | pace range on work steps, HR z1–2 on recovery |
| **Explore** | open-goal run with optional target distance = `longestRecentRunKm · 0.8` | HR zone 2–3 (advisory) |
| **Recover** | 20–30 min (shorter when `daysSinceLastRun ≤ 1`) | pace ≥ easyPace + 30 s, HR zone 1 |
Guard rails: if `daysSinceLastRun ≥ 7` or `weeklyKm < 8`, Build downgrades interval count;
all distances rounded to 100 m, times to whole minutes.

### 6.4 WorkoutKit mapping (`WorkoutKitBuilder`)
- Blueprint → `CustomWorkout(activity: .running, location: .outdoor, displayName:,
  warmup: WorkoutStep?, blocks: [IntervalBlock], cooldown:)`.
- Goals → `.distance(m, .meters)` / `.time(s, .seconds)` / `.open`.
- Alerts → `HeartRateZoneAlert` (`.heartRate(zone:)`), pace → `SpeedRangeAlert` over
  `Measurement<UnitSpeed>` (converted from sec/km), `metric: .current`.
- **Known WorkoutKit constraints honored, not worked around**: ±7-day scheduling window,
  reactive alerts only, fixed block iterations, explicit
  `WorkoutScheduler.authorizationState` handling.
- This file is the *only* place touching WorkoutKit types; if an API name shifted between
  SDK seeds, the fix is localized here.

### 6.5 Scheduling (`WorkoutSchedulerService`)
- `requestAuthorization()` → `WorkoutScheduler.shared.requestAuthorization()`.
- `schedule(blueprint, date)` → build `WorkoutPlan(.custom(workout), id: plannedWorkout.id)`,
  `WorkoutScheduler.shared.schedule(plan, at: DateComponents)` → persist `PlannedWorkout`
  with `statusRaw = scheduledOnWatch`.
- `removeAll()/remove(id:)` for cleanup; list via `WorkoutScheduler.shared.scheduledWorkouts`.
- Immediate use: SwiftUI `.workoutPreview(WorkoutPlan)` sheet (system UI offers
  "start on Watch").

### 6.6 UI
Workouts tab: today's suggestion banner (mode picked from load: `daysSinceLastRun ≥ 3 →
Maintain`, hard run yesterday → Recover, `runCount7d ≥ 3` and no quality session → Build …),
4 mode cards → generated preview (structure list + estimates) → actions: *Send to Watch
(schedule)* / *Preview* / *Regenerate variant*.

### 6.7 Tests
`TrainingLoadCalculatorTests` (windows, medians, fallbacks),
`InstantWorkoutGeneratorTests` (per-mode structure invariants: warmup exists, iterations
clamped, recovery steps have alerts, estimates within sane bounds; guard rails for low/no
history), blueprint JSON round-trip.

**Device-only acceptance**: generated Build workout appears in the Watch Workout app,
executes with working pace alerts.

---

## 7. Phase 4 — Training Plans (design, implemented after Phase 3 ships)

- **Templates** (data-driven, JSON in bundle): 5K (8 weeks), 10K (10 weeks), Half (12 weeks);
  3–4 sessions/week: easy / quality (intervals or tempo, reusing Phase 3 generators with a
  plan-week intensity parameter) / long run (+10 % weekly, cutback every 4th week −30 %).
- **Generation**: `PlanEngine.generate(template, startDate, currentLoad) -> [PlannedWorkout]`
  — first-week volume anchored to `TrainingLoadCalculator` output, not template absolutes.
- **Rolling sync job**: on every app foreground + a `BGAppRefreshTask`:
  1. fetch `WorkoutScheduler.shared.scheduledWorkouts`
  2. target set = plan workouts with `scheduledDate ∈ [now, now+7d]`
  3. schedule missing, remove stale/changed (WorkoutKit ±7-day visibility window).
- **Adherence**: after each sync, match completed `Activity` to `PlannedWorkout` on same
  calendar day (±1 day tolerance) + distance within 25 % → `completed` + link; planned
  workouts >36 h past due → `skipped`.
- **Adaptation (light)**: ≥2 skipped in a rolling week → shift remaining plan by re-basing
  next week's volume to `max(template, actual last week · 1.1)`; never increase >10 %/week.
  No exotic ML — deterministic and testable.
- Tests: template expansion invariants, rolling-window set difference, adherence matcher,
  adaptation bounds.

## 8. Phase 5 — Personal Heatmap (design)

- Decode all `encodedPolyline`s once into `[MKPolyline]` (cache in memory keyed by activity
  ID); render with one `MapPolyline` per activity in SwiftUI `Map`, stroke
  `.white.opacity(0.25)` on dark map style for additive feel.
- Filters (year, period, min distance) recompute the polyline set off-main.
- **Measure before optimizing**: if pan/zoom <60 fps with full history, switch to a
  pre-rasterized `MKTileOverlay` (render polylines into 256px tiles, LRU disk cache).
  The fallback is an internal renderer swap; UI unchanged.

## 9. Phase 6 — Route Builder / Suggested Routes (design)

- **Provider decision (ask user first)**: default recommendation **OpenRouteService** free
  tier (`/v2/directions/foot-walking` for snapping, `round_trip` options for loops;
  40 req/min free). Key stored in Keychain, entered in Settings.
- Manual builder: long-press adds waypoint → ORS directions between consecutive waypoints →
  merged geometry + distance + ascent; undo stack; save as `Route`.
- Suggested: `round_trip: {length, points: 3, seed}` ×3 seeds → 3 alternatives.
- GPX export: minimal `<trk>` writer from decoded polyline, shared via `ShareLink`.

## 10. Phase 7 — Offline Route Maps (design)

- **Provider decision (ask user first)**: recommendation — vector tiles via **Protomaps**
  (single `.pmtiles` extract per region, MapLibre Native renders it) — dramatically simpler
  storage story than raster tile trees.
- `MapLibre Native` via SPM **only** in the route-detail view; MapKit stays everywhere else.
- `OfflineMapService`: compute route bbox + 1 km buffer → download extract → store under
  `Application Support/OfflineMaps/<routeID>` → LRU cleanup with user-visible quota
  (default 2 GB) in Settings.
- Acceptance: airplane mode → saved route renders map + track.

---

## 11. Cross-cutting

### 11.1 Capabilities / plist (all declared in `project.yml`)
- HealthKit + background delivery entitlements; App Group `group.com.nicocalcagno.curra`.
- `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription` (WorkoutKit scheduling
  shows in Health permissions), `NSLocationWhenInUseUsageDescription` (map user dot),
  URL scheme `curra` (OAuth callback), `UIBackgroundModes: [fetch, processing]`.

### 11.2 Testing strategy
- Unit tests only (per master plan): engines + mappers + codecs. Run via
  `xcodebuild test -scheme Curra -destination 'platform=iOS Simulator,name=iPhone 15 Pro'`.
- Manual device checklist maintained in README (HealthKit sync, Watch scheduling, widget).

### 11.3 Commit conventions
Conventional commits, one atomic commit per task (`feat:`, `fix:`, `test:`, `docs:`,
`refactor:`).

### 11.4 Open decisions (unchanged from master plan)
1. Apple Developer Program — before daily use (nothing in code depends on it).
2. Routing provider — before Phase 6 implementation (recommendation: OpenRouteService).
3. Tile provider — before Phase 7 implementation (recommendation: Protomaps + MapLibre).

---

## 12. Execution order & current status

| Phase | Scope | Status |
|---|---|---|
| 0 | XcodeGen scaffold, capabilities, SwiftLint, app skeleton | **implemented in this repo** |
| 1 | Full SwiftData schema, polyline codec, Strava OAuth+import+rate limiter, HealthKit sync, dedup, coordinator, unit tests | **implemented in this repo** |
| 2 | GoalEngine, dashboard UI, goal editor/detail, history, widget | **implemented in this repo** |
| 3 | Load calculator, 4-mode generator, WorkoutKit builder/scheduler, workouts UI, unit tests | **implemented in this repo** |
| 4 | Training plans | next — after Phase 3 device validation |
| 5 | Heatmap | after Phase 1 data is on device |
| 6–7 | Routes + offline | after provider decisions |

> ⚠️ This repository was authored in a Linux environment without Xcode: the code compiles
> against documented iOS 17 APIs but has **not** been compiled here. First action on a Mac:
> `xcodegen generate`, open, build, and fix any SDK drift (most likely spots are isolated in
> `WorkoutKitBuilder.swift` / `WorkoutSchedulerService.swift`).
