-- Server schema.
--
-- Deliberately close to the mobile schema (see the Flutter app's
-- data/local/app_database.dart): the same Category -> Point -> Status ->
-- Comment -> Photos shape, the same wire values, the same template versioning.
-- Keeping them aligned is what lets an inspection be created on a phone and
-- read here without a translation layer.

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- People
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS users (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  email         TEXT NOT NULL UNIQUE,
  -- scrypt, stored as "salt:derivedKey" hex. No plaintext, ever.
  password_hash TEXT NOT NULL,
  -- admin: full access. reviewer: read inspections and media only.
  -- evaluator: the mobile app; cannot sign in to the dashboard.
  role          TEXT NOT NULL CHECK (role IN ('admin', 'reviewer', 'evaluator')),
  branch        TEXT,
  is_active     INTEGER NOT NULL DEFAULT 1,
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_users_role ON users (role);

-- Opaque bearer tokens. A row is the session; deleting it revokes access.
CREATE TABLE IF NOT EXISTS sessions (
  token      TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions (user_id);

-- ---------------------------------------------------------------------------
-- Checklist templates
-- ---------------------------------------------------------------------------

-- Versioned and immutable once published: editing a published template creates
-- the next version rather than mutating rows, so an inspection captured against
-- v1 keeps grading against v1 forever.
CREATE TABLE IF NOT EXISTS templates (
  id            TEXT    NOT NULL,
  version       INTEGER NOT NULL,
  name          TEXT    NOT NULL,
  description   TEXT,
  is_default    INTEGER NOT NULL DEFAULT 0,
  is_published  INTEGER NOT NULL DEFAULT 0,
  grading_rules TEXT    NOT NULL,
  created_by    TEXT REFERENCES users (id),
  created_at    TEXT    NOT NULL,
  updated_at    TEXT    NOT NULL,
  PRIMARY KEY (id, version)
);

CREATE TABLE IF NOT EXISTS template_categories (
  template_id      TEXT    NOT NULL,
  template_version INTEGER NOT NULL,
  id               TEXT    NOT NULL,
  code             TEXT    NOT NULL,
  title            TEXT    NOT NULL,
  icon_name        TEXT,
  sort_order       INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (template_id, template_version, id),
  FOREIGN KEY (template_id, template_version)
    REFERENCES templates (id, version) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS template_points (
  template_id            TEXT    NOT NULL,
  template_version       INTEGER NOT NULL,
  id                     TEXT    NOT NULL,
  category_id            TEXT    NOT NULL,
  code                   TEXT    NOT NULL,
  title                  TEXT    NOT NULL,
  description            TEXT,
  is_required            INTEGER NOT NULL DEFAULT 1,
  allows_na              INTEGER NOT NULL DEFAULT 1,
  requires_photo_on_fail INTEGER NOT NULL DEFAULT 0,
  max_photos             INTEGER NOT NULL DEFAULT 3,
  weight                 INTEGER NOT NULL DEFAULT 1,
  sort_order             INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (template_id, template_version, id),
  FOREIGN KEY (template_id, template_version)
    REFERENCES templates (id, version) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_points_category
  ON template_points (template_id, template_version, category_id, sort_order);

-- ---------------------------------------------------------------------------
-- Inspections
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS inspections (
  id                  TEXT PRIMARY KEY,
  -- The id the phone generated. Unique, and what makes re-submission
  -- idempotent when a response is lost after the server already committed.
  local_id            TEXT    NOT NULL UNIQUE,
  reference_number    TEXT    NOT NULL,
  template_id         TEXT    NOT NULL,
  template_version    INTEGER NOT NULL,
  evaluator_id        TEXT    NOT NULL,
  evaluator_name      TEXT    NOT NULL,
  registration_number TEXT    NOT NULL,
  make                TEXT    NOT NULL,
  model               TEXT    NOT NULL,
  manufacturing_year  INTEGER NOT NULL,
  vin                 TEXT    NOT NULL,
  mileage_km          INTEGER NOT NULL,
  status              TEXT    NOT NULL,
  score_percentage    REAL,
  grade_code          TEXT,
  obtained_points     INTEGER,
  max_points          INTEGER,
  total_items         INTEGER NOT NULL DEFAULT 0,
  completed_items     INTEGER NOT NULL DEFAULT 0,
  -- Set when a reviewer signs the inspection off in the dashboard.
  review_status       TEXT    NOT NULL DEFAULT 'pending'
                      CHECK (review_status IN ('pending', 'approved', 'rejected')),
  review_note         TEXT,
  reviewed_by         TEXT REFERENCES users (id),
  reviewed_at         TEXT,
  created_at          TEXT    NOT NULL,
  submitted_at        TEXT,
  received_at         TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_inspections_received ON inspections (received_at DESC);
CREATE INDEX IF NOT EXISTS idx_inspections_evaluator ON inspections (evaluator_id);
CREATE INDEX IF NOT EXISTS idx_inspections_grade ON inspections (grade_code);
CREATE INDEX IF NOT EXISTS idx_inspections_review ON inspections (review_status);
CREATE INDEX IF NOT EXISTS idx_inspections_registration ON inspections (registration_number);

CREATE TABLE IF NOT EXISTS inspection_items (
  id            TEXT PRIMARY KEY,
  inspection_id TEXT NOT NULL REFERENCES inspections (id) ON DELETE CASCADE,
  point_id      TEXT NOT NULL,
  status        TEXT NOT NULL,
  comment       TEXT,
  updated_at    TEXT
);

CREATE INDEX IF NOT EXISTS idx_items_inspection ON inspection_items (inspection_id);

CREATE TABLE IF NOT EXISTS inspection_photos (
  id            TEXT PRIMARY KEY,
  inspection_id TEXT    NOT NULL REFERENCES inspections (id) ON DELETE CASCADE,
  item_id       TEXT    NOT NULL,
  -- Path relative to the storage root, never an absolute host path.
  file_path     TEXT    NOT NULL,
  byte_size     INTEGER NOT NULL DEFAULT 0,
  content_type  TEXT,
  uploaded_at   TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_photos_inspection ON inspection_photos (inspection_id);
CREATE INDEX IF NOT EXISTS idx_photos_item ON inspection_photos (item_id);

-- ---------------------------------------------------------------------------
-- Audit
-- ---------------------------------------------------------------------------

-- Templates and grading rules decide what an inspection is worth, so every
-- change to them is recorded with who made it.
CREATE TABLE IF NOT EXISTS audit_log (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  actor_id    TEXT,
  actor_name  TEXT,
  action      TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id   TEXT,
  detail      TEXT,
  created_at  TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log (created_at DESC);
