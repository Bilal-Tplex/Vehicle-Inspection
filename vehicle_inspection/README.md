# Vehicle Inspection

An Android app for vehicle evaluators to capture, grade and submit inspections — built to keep working when the signal does not.

Flutter 3.47 / Dart 3.13 · Riverpod · SQLite · offline-first

---

## Table of contents

1. [What it does](#1-what-it-does)
2. [Running it](#2-running-it)
3. [Architecture](#3-architecture)
4. [The checklist is data, not code](#4-the-checklist-is-data-not-code)
5. [Offline and synchronisation](#5-offline-and-synchronisation)
6. [Grading](#6-grading)
7. [Photos](#7-photos)
8. [Error handling](#8-error-handling)
9. [Tests](#9-tests)
10. [Packages used](#10-packages-used)
11. [Assumptions](#11-assumptions)
12. [What I would do next](#12-what-i-would-do-next)

---

## Screenshots

All captured from the release APK running on an Android 15 emulator (Pixel 6, API 35).

| Login | Dashboard | New inspection | Checklist |
|---|---|---|---|
| ![Login](docs/screenshots/01-login.png) | ![Dashboard](docs/screenshots/02-dashboard.png) | ![New inspection](docs/screenshots/03-new-inspection.png) | ![Checklist](docs/screenshots/04-checklist.png) |

### The offline journey

This is the sequence that matters, captured with **Simulate offline** switched on for the first three frames.

| Live score | Summary | Submitted, offline | Pending | Reconnected |
|---|---|---|---|---|
| ![Live score](docs/screenshots/05-checklist-live-score.png) | ![Summary](docs/screenshots/06-summary.png) | ![Submitted](docs/screenshots/07-submitted-offline.png) | ![Pending](docs/screenshots/08-pending-sync.png) | ![Synced](docs/screenshots/09-synced.png) |

1. **Live score** — one Pass and one Fail: 2 of 4 possible points, `50.0%`, grade F. The progress counter, filter counts and per-category tally all fall out of the same calculation.
2. **Summary** — `100.0%`, grade A with its band range, the full breakdown, and a device-generated inspection ID.
3. **Submitted with no connection** — the evaluator still gets a confirmation, `INS-20260827-0AD3`, `50 of 50 points`, and an honest `Pending sync` rather than an error.
4. **Dashboard** — `1 pending · will sync when back online`.
5. **Reconnected** — the queue drains on its own and the same row reads `All inspections synced`.

Note the photo limits in the checklist shots: `5 left` on EXT-01 and `3 left` on SAF-04. Nothing in the UI knows those numbers — they come from `maxPhotos` on each point in the template JSON.

### Talking to the real backend

| Synced to the server | Template v1 | …then v2, pulled from the dashboard |
|---|---|---|
| ![Synced](docs/screenshots/11-synced-to-backend.png) | ![v1](docs/screenshots/12-template-v1.png) | ![v2](docs/screenshots/13-template-v2.png) |

The first frame is the same confirmation screen as above, but online against [`../backend`](../backend): it now shows a **server reference** (`ins_1be5938e…`) alongside the device-generated ID, and `Synced`.

The other two are the admin loop closing. A point was added and published as **v2** in the dashboard; the app pulled it with **Check for updates** and moved from `Version 1 · 25 points` to `Version 2 · 26 points`. No app release, no rebuild. Inspections captured before the publish still report `v1` and grade against it.

<details>
<summary>Settings, including the network simulation controls</summary>

![Settings](docs/screenshots/10-settings.png)

</details>

---

## 1. What it does

| Flow | Behaviour |
|---|---|
| **Login** | `evaluator@test.com` / `password123`. Validation, loading and error states; session cached in the platform keystore. There is a **Use test credentials** button on the login screen. |
| **Dashboard** | Evaluator name, completed / pending-sync / draft counters, New Inspection, My Inspections, and the five most recent inspections. |
| **New inspection** | Registration, make, model, year, VIN and mileage, each validated. Creates the draft in SQLite before the checklist opens. |
| **Checklist** | 25 points across 5 categories. Pass / Minor Issue / Fail / N/A, optional comment, photos. Live progress (`15/25 completed`) and a live score. Filter by All / Not checked / Issues; collapse categories. |
| **Summary** | Vehicle details, full breakdown, score, grade, every photo — with edit routes back to the vehicle form and the checklist. |
| **Submit** | Blocked until every required point is answered. Produces an inspection ID, score, grade and sync status. |
| **History** | Search and filter, sync status per row, tap to open. Drafts resume, submitted inspections open read-only. |
| **Settings** | Theme, and switches that simulate offline / server errors / latency so the sync behaviour can be reviewed without airplane mode. |

Also included: dark mode, a live sync banner, manual retry for failed uploads, and 94 unit, widget and on-device integration tests.

---

## 2. Running it

### Prerequisites

- Flutter **3.47.1** or newer (Dart 3.13+)
- JDK **17**
- Android SDK — platform **36** and build-tools **36.0.0** cover it; Gradle fetches anything else a plugin asks for on first build
- A device or emulator on **Android 6.0 (API 23)** or newer

### Run

```bash
flutter pub get
```

The app talks to the backend in [`../backend`](../backend), which also serves the admin dashboard. Start it first:

```bash
cd ../backend && npm install && npm start
```

Then run the app. It defaults to `http://10.0.2.2:4000/v1` — how an Android emulator reaches the host machine:

```bash
flutter run
```

For a physical handset, point it at your machine's LAN address (and add that IP to `android/app/src/main/res/xml/network_security_config.xml`):

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:4000/v1
```

To run standalone with no server at all, against the in-app mock backend:

```bash
flutter run --dart-define=USE_MOCK_API=true
```

### Build the APK

```bash
flutter build apk --release
```

The APK lands at `build/app/outputs/flutter-apk/app-release.apk`.

> **Signing:** the release build uses the standard Flutter debug signing config (`android/app/build.gradle.kts`), so the APK installs directly for review. A production build would add a real keystore and a `signingConfigs.release` block.

For a smaller download, split per ABI:

```bash
flutter build apk --release --split-per-abi
```

### Tests and analysis

```bash
flutter test
```

```bash
flutter analyze
```

On-device tests need a running emulator or a connected handset:

```bash
flutter test integration_test/app_test.dart
```

> Running those bakes the `integration_test` plugin into Flutter's generated plugin registrant, which then fails a subsequent `--release` build (`package dev.flutter.plugins.integration_test does not exist`). It is a Flutter tooling quirk, not a project one — `flutter clean` before the release build clears it.

Both are clean: 89 host tests pass (plus 5 on-device), and `flutter analyze` reports no issues under a lint set that is stricter than `flutter_lints` (see `analysis_options.yaml`).

### Trying the offline behaviour

The point of the app is what happens with no signal, so there are two ways to exercise it:

1. **Settings → Simulate offline.** The whole app treats the device as having no connection: the sync engine holds everything in the queue and the banner says so. Complete an inspection, submit it, and watch it wait.
2. **Airplane mode**, or just stopping the backend. Same result through the real connectivity plugin and real request failures.

Either way: submission still succeeds, the summary and inspection ID still appear, the banner reports what is pending, and everything uploads when you switch back. The **Server error rate** slider forces 503s so you can watch the retry/backoff path, and **Response latency** slows uploads enough to see the progress states.

---

## 3. Architecture

Four layers, dependencies pointing inwards only.

```
lib/
├── main.dart                     Entry point, global error handler
└── src/
    ├── app/                      MaterialApp, routing, theme, composition root
    │   ├── providers.dart        Every dependency, wired once
    │   ├── router.dart           Named routes and argument checking
    │   └── theme/                Light + dark, semantic status colours
    │
    ├── core/                     Cross-cutting, feature-agnostic
    │   ├── constants/            Tunables (photo limits, backoff, timeouts)
    │   ├── error/                Failure hierarchy + one exception→failure mapper
    │   ├── network/              ApiClient interface
    │   ├── utils/                Validators, formatters, logger
    │   └── widgets/              Shared UI (status pills, grade badge, empty/error views)
    │
    ├── domain/                   Pure Dart. No Flutter, no SQL, no HTTP.
    │   ├── entities/             Inspection, Vehicle, Template, GradingRules …
    │   ├── repositories/         Abstract contracts
    │   └── services/             GradingService, PhotoService, ConnectivityMonitor
    │
    ├── data/                     Implements the domain contracts
    │   ├── local/                SQLite schema, DAOs, secure session store
    │   ├── remote/               API classes + the mock backend
    │   ├── repositories/         Offline-first orchestration
    │   └── services/             Platform photo capture, connectivity
    │
    ├── sync/                     The outbox: queue, engine, state
    └── features/                 One folder per screen area
        ├── auth/  dashboard/  inspection/  history/  settings/  sync/
```

### The rules that shape it

**The domain layer has no dependencies.** `grading_service.dart` imports nothing but other domain files. That is why grading can be unit-tested without a database, a widget, or a mock — and why the same calculation could later run on the server unchanged.

**Repositories are the only place data comes from.** Controllers depend on `InspectionRepository` (an interface), never on a DAO or an API. Swapping the mock backend for a real one is a one-line change in `providers.dart`.

**The database is the source of truth, not a cache.** Every write lands in SQLite and returns immediately. Nothing in the app awaits the network — see [§5](#5-offline-and-synchronisation).

**State management: Riverpod.** Chosen for compile-time-safe dependency injection and easy test overrides. No code generation is used anywhere in this project, so `flutter pub get` is the only step before building — there is no `build_runner` to run and no generated files to keep in sync.

**One screen, one async value.** `InspectionSession` bundles the inspection, its template and its live grade, so screens never juggle three separate futures that can arrive out of order.

**Change notification lives on the DAO, not the repository.** Both the repository and the sync engine write through `InspectionDao`, so that is where the "something changed" signal belongs. Put it a layer higher and a background upload would update the database without updating the screen — a record would keep reading "Pending sync" long after it had landed. There is a regression test for exactly that.

### Data model

```
InspectionTemplate (id + version)
 └── InspectionCategory
      └── InspectionPoint          title, required?, allows N/A, max photos, weight

Inspection (local UUID + reference number)
 └── InspectionItem                one per point, created up front
      ├── ItemStatus               pass | minor_issue | fail | na | pending
      ├── comment
      └── InspectionPhoto[]        own file, own sync state
```

Seven tables, fully normalised, foreign keys on, `PRAGMA foreign_keys = ON` set in `onConfigure` (SQLite ignores them otherwise). Schema and rationale are in `data/local/app_database.dart`; migrations are forward-only, because an unsynced inspection has to survive an app update.

Two deliberate denormalisations: `completed_items` / `total_items` counters, and the grade snapshot (`score_percentage`, `grade_code`) on the inspection row. Both let the history list render without loading items and photos — the difference between a snappy list and a slow one once a device holds hundreds of inspections.

---

## 4. The checklist is data, not code

This is the requirement that most shapes the design: 25 points today, 209+ later, without rewriting the UI.

The checklist ships as **`assets/templates/standard_inspection_v1.json`** — not as Dart. On first launch it is parsed into the `templates` / `template_categories` / `template_points` tables. The JSON has exactly the shape `TemplateApi.fetchTemplates()` returns, so when the admin dashboard starts publishing templates, `refreshFromRemote()` replaces the seed and **nothing else in the app changes**.

There is exactly one widget for a checklist point (`ChecklistPointTile`) and one for a category header. The checklist screen flattens categories and points into a single lazily-built list, so:

- 209 points cost the same in code as 25, and only visible rows are constructed.
- Adding, removing or reordering points is a data change.
- An admin can mark a point required, allow or forbid N/A, set its photo limit, demand a photo on failure, or weight it — all from the template.

**Templates are versioned**, and an inspection stores the `(template_id, template_version)` it was captured against. Publishing v2 of a checklist cannot retroactively change a completed inspection's questions or its score.

Categories carry an `iconName` string rather than an icon, so a new category from the backend renders sensibly without an app release.

---

## 5. Offline and synchronisation

**The design in one line: nothing in the app awaits the network.**

Every repository method completes against SQLite. Submitting an inspection writes the grade, marks it submitted, enqueues the work, and returns — whether or not there is signal. There is no "waiting for the server" state anywhere in the UI, because there is nothing to wait for.

### The outbox

Pending work lives in a **`sync_queue` table**, not in memory. It survives the app being killed, the phone rebooting, or an evaluator finishing a shift and opening the app the next morning.

```
sync_queue(entity_type, entity_id, operation, attempts, next_attempt_at, last_error)
UNIQUE(entity_type, entity_id, operation)
```

The unique constraint means tapping "retry" repeatedly updates one row instead of flooding the queue.

### One task per photo

Submitting an inspection with 20 photos enqueues **21 tasks**: one for the record, twenty for the files. On a weak connection the upload makes progress file by file instead of restarting from zero every time it drops. Photos are addressed by the server-assigned inspection id, so a photo task whose parent has not been accepted yet is **deferred, not failed** — it stays queued without consuming a retry.

An inspection is only marked `synced` once its record *and* every photo have landed. Until then it honestly reports `pending`.

### Retry policy

Backoff is exponential and capped: **4s → 8s → 16s → 32s …, ceiling 30 minutes, 5 attempts**. A server outage costs battery once rather than continuously.

Crucially, *retryable* is a property of the failure, not of the call site:

| Failure | Retried? | Why |
|---|---|---|
| Offline / socket / timeout | ✅ | The request never reached the server |
| 5xx, 429 | ✅ | The server may recover |
| 401 / 403 | ❌ | Needs re-authentication, not a retry |
| 422 | ❌ | Resending the same payload fails identically |

When the budget is exhausted the record is marked `failed`, the work stays on the device, and the evaluator gets a **Retry sync now** button on the inspection detail screen.

### Triggers and safety

- `connectivity_plus` transitions — coming back online starts a drain.
- App startup — anything left from last session.
- Submission, and manual taps on the banner or Settings.

Runs are **serialised**: a connectivity flap mid-run sets a rerun flag rather than starting a second overlapping drain. Requests are **debounced** (2s) so a burst of flaps triggers one drain. Connectivity is re-checked *between tasks*, so a batch stops cleanly when signal drops mid-way instead of burning the retry budget.

Submission sends the local id so the backend can treat a repeated call as **idempotent** — essential when a response is lost after the server has already committed. The mock backend implements this, and there is a test for it.

One acknowledged limitation, called out in the code: the platform reporting an active interface is not proof the API is reachable (captive portals, dead backhaul). Connectivity is therefore treated as a hint, and the engine still handles request failures as the real authority.

### What the evaluator sees

A banner reports `Pending sync`, `Uploading 3 of 12`, `Waiting for connection` or `Sync failed`, with a progress bar during a run, and it hides itself entirely when everything is synced. Every history row and photo thumbnail carries its own sync chip.

---

## 6. Grading

`domain/services/grading_service.dart` — a pure function of `(answers, rules)`. No Flutter, no persistence, no network.

```
Pass = 2 · Minor Issue = 1 · Fail = 0 · N/A excluded
percentage = obtained / maximum × 100
90+ A · 80+ B · 70+ C · 60+ D · below F
```

The specification's worked example is a test:

```dart
// 14 passes (28) + 6 minor issues (6) = 34 of 40
expect(result.percentage, 85);
expect(result.gradeCode, 'B');
```

### The rules are data

`GradingRules` is a serialisable object — status points, the maximum per item, excluded statuses and the grade bands — carried **on the template** and stored in the `templates` table. An admin dashboard can publish a stricter scale for commercial vehicles without an app release. A test does exactly that: it regrades the same answers under a pass/fail scale and gets `FAIL` instead of `B`.

### Details that matter

- **N/A is removed from the maximum, not scored as zero.** A vehicle without a sunroof is not penalised for not having one.
- **Unanswered points are excluded too**, so the live score during an inspection is meaningful instead of climbing from 0%.
- **Bands are defined by their lower bound** and matched highest-first, so they can never leave a gap — 89.4% is a B, not ungraded.
- **Nothing scorable yet reads as "Ungraded", not F.** A blank inspection has not failed.
- **Points can be weighted.** The shipped template uses weight 1 everywhere to match the specification exactly, but the engine honours weights and a test proves it.
- The grade is recomputed on **every** answer change and cached on the inspection row, so the number shown while inspecting is the number that gets submitted.

---

## 7. Photos

Camera or gallery, multiple per point, with preview (pinch to zoom), delete and replace.

**Compression happens at capture, not at upload.** An evaluator can shoot 40 photos in a basement with no signal; keeping originals would fill the device and make the eventual upload far slower. Each photo is resized to a 1600px bound and re-encoded as JPEG at quality 78 — typically a 3–5 MB capture down to 150–350 KB. Original and final sizes are logged.

Files live in app-private storage under `inspection_photos/<inspectionId>/`, so discarding a draft is one directory delete. Only the path and metadata go in the database. Dimensions are read from the JPEG header via `ImageDescriptor` rather than decoding the full bitmap.

Two rules worth noting: **cancelling the picker is not an error** (it returns `null` and the inspection is untouched), and **replace captures the new photo before deleting the old one**, so cancelling a replace cannot lose the original. A missing file renders a placeholder rather than crashing the checklist.

The template can require a photo when a point is failed (`requiresPhotoOnFail`) — six points in the shipped checklist do — and submission is blocked until the evidence is attached.

---

## 8. Error handling

One function, `core/error/failure_mapper.dart`, translates everything thrown below the repository line into a typed `Failure` carrying a user-safe message and an honest `isRetryable`. That is why there are no `catch (e)` blocks in controllers or widgets.

| Area | Behaviour |
|---|---|
| Login | Inline error under the form (not a snackbar that vanishes mid-read); wrong credentials, offline and server errors read differently |
| Validation | Per-field messages; VIN rejects I/O/Q per ISO 3779; submission lists exactly which points block it and jumps to them |
| Uploads | Typed retryable/terminal split, backoff, manual retry |
| Storage | A corrupt session is discarded as "signed out" rather than bricking the app; a full disk surfaces as an actionable message |
| Camera | A denied permission gets different advice from a broken camera |
| Sync | An inspection deleted while queued is dropped cleanly instead of wedging the queue (tested) |

Errors that should not interrupt work do not: a failed photo attach shows a snackbar over the intact checklist rather than replacing the screen.

---

## 9. Tests

**94 tests, all passing** — 89 on the host, 5 on a real Android device. They target the parts where being wrong is expensive.

```bash
flutter test
```

| File | Covers |
|---|---|
| `test/domain/grading_service_test.dart` | The spec's worked example, N/A and pending exclusion, band boundaries, weighting, configurable rules, JSON round trip, divide-by-zero |
| `test/data/inspection_repository_test.dart` | Draft creation, answering, comments, photo limits, replace/delete, submission blocking, grade snapshot, queueing, filters, search, live stream, cascade delete |
| `test/sync/sync_engine_test.dart` | Offline queueing, drain on reconnect, per-photo progress, deferred photos, retryable vs terminal failures, backoff windows, idempotency, manual retry, deleted-while-queued, state reporting |
| `test/core/validators_test.dart` | Email, password, VIN, year, mileage, registration |
| `test/app/inspection_flow_test.dart` | The real widget tree: sign-in and its failure modes, form validation, checklist rendering from template data, live score, blocked review, summary, submission, history, read-only detail, sync banner states |
| `integration_test/app_test.dart` | **On a real device:** real SQLite schema, the 25-point checklist seeded out of the APK asset, the Android keystore, and a full offline submission that queues and then syncs on reconnect |

The repository and sync tests run against a **real SQLite database** (`sqflite_common_ffi`, in-memory), so the actual schema, foreign keys and cascades are exercised rather than mocked away.

The widget tests drive the **real app widget tree** — every screen, controller, route and the grading service are the production ones — with in-memory fakes below the repository line. That split is forced rather than chosen: `sqflite_common_ffi` does its work off the Dart event loop, and `testWidgets` runs under a fake clock, so a query started inside a widget test never completes. Keeping the two suites separate means each covers its layer properly.

They earned their keep immediately: the submission flow was calling `pushNamedAndRemoveUntil` with a predicate matching the dashboard's *route name*. Because the dashboard is the root gate's content rather than a pushed route, the predicate matched nothing, the whole stack was unwound, and "Back to dashboard" left the evaluator stranded on the confirmation screen. Nothing in the unit tests could have seen that.

---

## 10. Packages used

| Package | Why |
|---|---|
| `flutter_riverpod` | State management and DI. Compile-safe, trivially overridable in tests, no codegen needed. |
| `sqflite` | Local database. Mature, plain SQL, full control over schema and migrations — which matters when unsynced data must survive updates. |
| `path` / `path_provider` | Database and photo-storage locations. |
| `connectivity_plus` | Network transitions that trigger sync. |
| `image_picker` | Camera and gallery. |
| `flutter_image_compress` | Native compression at capture time. |
| `flutter_secure_storage` | Session token in the platform keystore (EncryptedSharedPreferences), not plain shared preferences — inspector phones are shared, field-used devices. **Pinned to 9.2.4:** 11.x hard-codes `compileSdk = 37`, and no published Android platform package provides a plain `android-37` (the SDK ships `android-37.0` / `37.1`), so it cannot currently be built. |
| `uuid` | Device-generated ids, so records are valid before the server sees them. |
| `http` | The real backend client (`HttpApiClient`). Chosen over `dio` because the app makes four calls and needs no interceptors yet. |
| `intl` | Date and number formatting. |
| `mocktail`, `sqflite_common_ffi` | Test doubles and an in-memory database. |

**Not used, deliberately:** any code generator. `freezed`, `json_serializable` and `riverpod_generator` would each add a `build_runner` step and generated files to the repo. `fromJson`/`toJson`/`copyWith` are hand-written instead, so a fresh clone builds with `flutter pub get` and nothing else.

---

## 11. Assumptions

1. **The backend is real and lives in [`../backend`](../backend).** The app talks to it over HTTP by default and submits there; that repo also serves the admin dashboard. `MockApiClient` is still present behind `--dart-define=USE_MOCK_API=true` so the app can be demoed standalone, and it implements the same `ApiClient` interface including latency, auth tokens, 4xx/5xx responses, multipart uploads and idempotency. Moving from one to the other cost exactly one new class (`HttpApiClient`) and one branch in `providers.dart` — no repository, controller, screen or test changed.
2. **Authentication is mocked** to `evaluator@test.com` / `password123`, as the brief allows. Token refresh is not implemented; an expired token is deliberately still accepted for local work, and the sync engine surfaces the 401 when it next runs.
3. **The 25 points are representative, not authoritative.** They are a plausible subset of a 209-point programme. Since the checklist is JSON, the real list drops in without code changes.
4. **`pending` is an internal fifth status.** The four statuses in the brief are what the evaluator picks; `pending` is the initial state that makes "15/25 completed" and required-point blocking possible.
5. **Optional points left unanswered are excluded from the score**, exactly like N/A. Only required points block submission.
6. **Submitted inspections are immutable** on the device. The brief allows editing *before* final submission, so the edit routes are on the summary screen; afterwards the record is read-only.
7. **`requiresPhotoOnFail` is an addition** to the brief, enabled on the six points where a defect is worth photographing: body panels, underbody corrosion, oil leakage, both tyre-tread points, and brake performance. When one of those is marked **Fail**, submission is blocked until a photo is attached. It fires on Fail only, never on Minor Issue, and it is a per-point template flag an admin can switch off — but be aware of it when testing. The shipped checklist has 25 points, 22 required and 3 optional.
8. **Reference numbers are generated on-device** (`INS-YYYYMMDD-XXXX`) so an evaluator has an ID to quote while offline. Uniqueness is enforced by a `UNIQUE` constraint; the random suffix makes a same-day cross-device collision negligible. The server id is stored separately and never replaces it.
9. **Release APK uses debug signing** so it installs directly for review. See [§2](#2-running-it).
10. **Portrait only.** Inspectors work one-handed around a vehicle.
11. **English only, metric only.** Localisation and unit preferences are listed as bonus items; the formatting already goes through `intl`, so adding locales is additive.
12. **Theme choice is in-memory**, not persisted — a one-line `SharedPreferences` write that touches nothing else.

---

## 12. What I would do next

Honest list of what a production version needs that this does not have, and how I would approach each.

**Background sync.** Today syncing needs the app in the foreground. In production I would add `workmanager` with a periodic constrained job (network-connected, battery-not-low) that drains the same `SyncQueue`. The queue lives in SQLite precisely so a background isolate can use it unchanged — the engine already takes its dependencies by constructor.

**Real upload progress.** `ApiClient.uploadFile` returns a future; a Dio-based implementation would expose `onSendProgress`, which the `SyncState` fields (`completedInRun` / `totalInRun`) are already shaped to carry per byte rather than per file.

**Token refresh.** An interceptor that catches 401, refreshes once, and replays the request; sign-out only if the refresh itself fails.

**PDF reports.** `pdf` + `printing`, generated from the same `GradingResult` the summary screen renders — the calculation is already UI-independent.

**Widget and integration tests.** The unit and repository layers are covered. I would add `integration_test` coverage of the full offline → submit → reconnect → synced journey, and golden tests for the checklist tile.

**Photo storage ceiling.** A device that never reconnects will accumulate photos indefinitely. I would add a retention policy: delete local files once `remote_url` is set and the record is confirmed synced.

**A template picker in the app.** The backend can serve several published templates and the app pulls all of them, but new inspections always use the default. Choosing between "Standard" and, say, "Commercial Vehicle" at the start of an inspection is a screen and one field on the draft — the data model already carries `templateId` and `templateVersion` per inspection.

**Conflict resolution.** Currently submission is create-only and idempotent by local id, which is correct while inspections are authored on exactly one device. If reviewers start editing server-side, this needs a real strategy — most likely last-write-wins per field with an `updated_at` per item, since inspections are append-heavy and rarely contested.
