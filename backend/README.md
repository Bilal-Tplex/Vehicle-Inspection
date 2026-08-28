# Vehicle Inspection — API & Admin Dashboard

The backend the mobile app submits to, and the dashboard admins run the programme from.

Node 22 · Express · SQLite (`node:sqlite`) · zero-build vanilla-JS dashboard

---

## What it covers

The brief listed the production dashboard as future scope (§15). This implements that list:

| Requirement | Where |
|---|---|
| Create / edit templates | Templates → New template, and the editor |
| Add / remove / reorder points | Template editor — drag a point by its handle, or move whole categories with ↑ ↓ |
| Configure grading rules | Template editor → Grading rules (status points, max per point, grade bands) |
| Manage evaluators and roles | Evaluators & roles — create, edit, change role, deactivate, reset password |
| View inspections | Inspections — search, filter by grade and review state, paginate, open in full |
| Review media | Inspection detail — gallery and per-point thumbnails, click for a keyboard-pageable lightbox |
| Generate reports | Reports — grade distribution, evaluator performance, top defects, activity log, CSV export |

Plus what the app needs to function: authentication, template delivery, inspection intake, and photo upload.

---

## Running it

```bash
npm install
```

```bash
npm start
```

That serves the dashboard on **http://localhost:4000** and the API on **/v1**. The database and an initial checklist are created on first boot — there is no separate setup step and no database server to install.

| Account | Password | Can do |
|---|---|---|
| `admin@test.com` | `admin123` | Everything |
| `reviewer@test.com` | `reviewer123` | Read inspections and media, approve/reject |
| `evaluator@test.com` | `password123` | Mobile app only — cannot sign in to the dashboard |

To wipe everything and start clean:

```bash
npm run reset
```

---

## How the app connects

The mobile app defaults to `http://10.0.2.2:4000/v1` — how an Android emulator reaches the host machine. For a physical handset, pass your LAN address and add it to the app's `network_security_config.xml`:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:4000/v1
```

The four endpoints the app uses are the entire contract:

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/v1/auth/login` | Sign in, returns a bearer token and the evaluator profile |
| `GET` | `/v1/templates` | Published checklists — **this is how a published template reaches the field** |
| `POST` | `/v1/inspections` | Submit a completed inspection |
| `POST` | `/v1/inspections/:id/photos` | Upload one photo, multipart |

Everything else lives under `/v1/admin/*` and `/v1/media/*` and is dashboard-only.

---

## Decisions worth explaining

**The server regrades every submission.** The phone computes the score so it can work offline, but a client-supplied number is not evidence. `services/grading.js` is a deliberate mirror of the app's `GradingService` — same status points, same exclusions, same highest-first band matching — and every submission is recomputed against the template it names. The server's number is what gets stored. A disagreement is written to the audit log as `inspection.grade_mismatch` rather than silently accepted, because a mismatch means the two implementations have drifted and someone should look.

**Submission is idempotent on the device-generated id.** The app retries until something sticks, which means the same inspection can legitimately arrive twice — a response lost after the server already committed looks identical to a failure. `local_id` is `UNIQUE`, and a repeat returns the original server id with `duplicate: true`.

**Identity comes from the token, not the payload.** The submitted JSON carries an `evaluatorId`, and the server ignores it in favour of whoever the bearer token belongs to. A client should not be able to attribute an inspection to a colleague.

**Template versions are immutable once published.** Editing a published template opens the next version as a draft; publishing swaps which version new inspections use. An inspection stores `(template_id, template_version)`, so its questions and its grading scale can never be rewritten under it. That is also why a point deleted from v2 still renders in a v1 inspection — the detail view resolves each answer against the revision it was captured with, and falls back to "Removed from template" rather than dropping the answer.

**Media is authenticated.** `/v1/media/:id` requires a token, so the dashboard fetches images as blobs rather than putting them in `<img src>`. Inspection photos can show vehicle interiors, plates and paperwork; they are not public URLs.

**No build step for the dashboard.** It is ES modules, served as-is. That is a deliberate trade: an internal admin tool does not justify a bundler, a lockfile of build dependencies, and a compile step between editing a file and seeing the change. If it grew past this size the answer would be Vite and a component framework.

**`node:sqlite` rather than `better-sqlite3`.** Built into Node 22, so there is no native compilation, no `node-gyp`, and no toolchain prerequisite. The trade-off is single-writer, which is right for one dashboard and a handful of phones and would become Postgres before this carried real load.

---

## Layout

```
backend/
├── src/
│   ├── index.js              Express bootstrap, route mounting, static dashboard
│   ├── config.js             Ports, paths, limits, scrypt parameters
│   ├── db/
│   │   ├── schema.sql        Tables, indexes, constraints
│   │   ├── database.js       Connection, PRAGMAs, transaction helper
│   │   ├── seed.js           First-run accounts and checklist
│   │   └── standard-template.json   Same 25 points the app bundles
│   ├── middleware/
│   │   ├── auth.js           Bearer tokens, role guards
│   │   └── errors.js         ApiError, one JSON error shape
│   ├── routes/
│   │   ├── auth.js  templates.js  inspections.js  users.js  reports.js
│   └── services/
│       ├── grading.js        Authoritative scoring, mirrors the app
│       ├── templates.js      Versioned read/write and serialisation
│       ├── security.js       scrypt hashing, token generation
│       └── audit.js          Who changed what
├── public/                   The dashboard (no build step)
│   ├── index.html
│   └── assets/
│       ├── styles.css        Design tokens, light + dark
│       ├── api.js            Fetch wrapper, session, auto sign-out on 401
│       ├── ui.js             DOM helpers, formatting, modal, toast, lightbox
│       ├── router.js         Hash router
│       ├── app.js            Shell, navigation, theme
│       └── views/            One module per screen
├── data/                     SQLite file (created on first run)
└── storage/photos/           Uploaded media, by inspection
```

---

## Security notes

What is in place: scrypt password hashing with per-password salts and constant-time comparison; opaque server-side tokens that can be revoked by deleting a row; role checks on every dashboard route; upload type and size limits; path-traversal guards on media reads; the last active admin cannot lock themselves out; deactivating an account or resetting a password drops its sessions immediately.

What a production deployment would still need: HTTPS (the app permits cleartext only to `10.0.2.2` and `localhost`, via an explicit Android network-security config); rate limiting on `/auth/login`; a rotating refresh-token scheme rather than 30-day bearers; object storage for media instead of local disk; and Postgres in place of SQLite.

---

## Screenshots

Captured from the running dashboard at 1600px, signed in as `admin@test.com`, with two inspections submitted from the Android app.

| Overview | Inspections |
|---|---|
| ![Overview](docs/screenshots/admin-01-overview.png) | ![Inspections](docs/screenshots/admin-02-inspections.png) |

| Inspection detail | Template editor |
|---|---|
| ![Detail](docs/screenshots/admin-03-inspection-detail.png) | ![Editor](docs/screenshots/admin-05-template-editor.png) |

| Templates | Evaluators & roles | Reports |
|---|---|---|
| ![Templates](docs/screenshots/admin-04-templates.png) | ![Users](docs/screenshots/admin-06-users.png) | ![Reports](docs/screenshots/admin-07-reports.png) |

<details>
<summary>Dark theme</summary>

![Dark](docs/screenshots/admin-08-overview-dark.png)

</details>

A few things visible in these that are worth pointing out:

- **Inspection detail** resolves every answer against the template revision it was captured with — `Standard Vehicle Inspection v1`, even though v2 is now the published default. Its two `Fail` rows are the ones the evaluator recorded on the phone.
- **Template editor** shows `v2 published`, a version history of `v2, v1`, and `EXT-07 New inspection point` — the point added through this screen and published, which the app then pulled without a rebuild.
- The **Required / Optional / Photo** chips on each point are the template flags the mobile checklist enforces: which points block submission, and which demand a photo when failed.
