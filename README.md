# Vehicle Inspection — Developer Test Project

Two projects that make one system: an offline-first Android app for evaluators in the field, and the backend plus admin dashboard behind it.

```
Vehicle/
├── vehicle_inspection/   Flutter Android app  →  README
└── backend/              Node API + admin dashboard  →  README
```

| | [`vehicle_inspection/`](vehicle_inspection) | [`backend/`](backend) |
|---|---|---|
| **What** | The evaluator's app | The API and the admin dashboard |
| **Stack** | Flutter 3.47, Riverpod, SQLite | Node 22, Express, SQLite |
| **Run** | `flutter run` | `npm start` → http://localhost:4000 |
| **Docs** | [README](vehicle_inspection/README.md) | [README](backend/README.md) |

---

## Getting both running

**1. Start the backend.** It creates its database and seeds the checklist on first boot.

```bash
cd backend && npm install && npm start
```

**2. Run the app.** It defaults to `http://10.0.2.2:4000/v1`, which is how an Android emulator reaches the host machine.

```bash
cd vehicle_inspection && flutter pub get && flutter run
```

**3. Sign in.**

| Where | Account | Password |
|---|---|---|
| Mobile app | `evaluator@test.com` | `password123` |
| Dashboard | `admin@test.com` | `admin123` |
| Dashboard, read-only | `reviewer@test.com` | `reviewer123` |

The app also runs standalone with no server at all — `flutter run --dart-define=USE_MOCK_API=true` — which is worth knowing when you only want to look at the app.

---

## How they fit together

```
   PHONE (offline-first)                          SERVER
   ─────────────────────                          ──────
   capture → SQLite ──┐
                      │  outbox (sync_queue)
                      └──► when online ──► POST /v1/inspections   ──► regrade, store
                                           POST /.../photos       ──► store media
                                           GET  /v1/templates ◄──── publish checklist
                                                                        ▲
                                                                   ADMIN DASHBOARD
```

Three things are worth pointing out about that picture.

**The arrow into the phone matters as much as the one out of it.** An admin edits a checklist in the dashboard and publishes it; the app pulls it on next launch and every new inspection uses it. No app release. The checklist is data on both sides — same JSON, same ids, same versioning.

**The phone never waits for the server.** Every write lands in the device's own SQLite first. Submission grades locally, produces an inspection ID, and queues. An evaluator in a basement gets a complete, valid record; the network is a replication detail that catches up later.

**The server does not trust the phone's score.** It regrades every submission against the template that submission names, using a deliberate mirror of the app's grading service, and stores its own answer. A disagreement is logged rather than swallowed.

---

## What was asked for, and where it lives

The brief scoped the dashboard as future work and asked that the app be built so it could be added "without a complete rewrite". Both halves are here, and the second one is the evidence for the first: moving the app from its mock backend to the real one cost **one new class and one branch** — no repository, controller, screen or test changed.

| Brief | Where |
|---|---|
| §2–§12 — login, dashboard, checklist, photos, offline, grading, summary, submit, history | [App README](vehicle_inspection/README.md) |
| §13 — data-driven checklist that scales to 209+ points | [App README §4](vehicle_inspection/README.md#4-the-checklist-is-data-not-code) |
| §15 — templates, points, grading rules, evaluators, roles, inspections, media, reports | [Backend README](backend/README.md#what-it-covers) |
| §17 — deliverables, architecture, packages, sync approach, grading, assumptions | Both READMEs |

Verified end to end on an Android 15 emulator: an inspection captured on the phone, submitted over HTTP, regraded server-side, and visible in the dashboard with its media and full checklist.
