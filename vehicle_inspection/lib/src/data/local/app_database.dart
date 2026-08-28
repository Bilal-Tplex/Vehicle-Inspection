import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/exceptions.dart';
import '../../core/utils/app_logger.dart';

/// Table and column names in one place, so a typo is a compile error rather
/// than a runtime one.
class Tables {
  const Tables._();

  static const String templates = 'templates';
  static const String templateCategories = 'template_categories';
  static const String templatePoints = 'template_points';
  static const String inspections = 'inspections';
  static const String inspectionItems = 'inspection_items';
  static const String inspectionPhotos = 'inspection_photos';
  static const String syncQueue = 'sync_queue';
}

/// Owns the SQLite connection and the schema.
///
/// The database is the app's source of truth. Every screen reads from it and
/// every write lands here first, which is what makes the whole app work with
/// the radio switched off — the network is an eventual replication detail, not
/// a prerequisite.
///
/// Schema notes:
/// * Templates are versioned. Categories and points are keyed by
///   `(template_id, template_version)` so publishing v2 of a checklist never
///   mutates the definition an already-completed inspection was captured
///   against.
/// * Answers are normalised into [Tables.inspectionItems] rather than stored as
///   a JSON blob, so 209 points per inspection stays a row count, not a
///   parse cost, and per-category progress is a single indexed query.
/// * Photos are their own rows with their own sync state, so a failed upload
///   retries one file instead of the whole inspection.
class AppDatabase {
  AppDatabase({DatabaseFactory? factoryOverride, String? pathOverride})
      : _factory = factoryOverride,
        _path = pathOverride;

  final DatabaseFactory? _factory;
  final String? _path;

  Database? _database;

  /// Opens on first use and reuses the handle afterwards.
  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;
    final opened = await _open();
    _database = opened;
    return opened;
  }

  Future<Database> _open() async {
    try {
      final factory = _factory ?? databaseFactory;
      final path = _path ??
          p.join(await factory.getDatabasesPath(), AppConstants.databaseName);

      return await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: AppConstants.databaseVersion,
          onConfigure: _onConfigure,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to open database',
        scope: 'db',
        error: error,
        stackTrace: stackTrace,
      );
      throw LocalStorageException('Could not open the local database',
          cause: error);
    }
  }

  /// Foreign keys are off by default in SQLite; without this, the cascade
  /// deletes below silently do nothing.
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    AppLogger.info('Creating schema v$version', scope: 'db');
    final batch = db.batch();
    for (final statement in _schemaV1) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
  }

  /// Forward-only migrations.
  ///
  /// Each version gets its own `if`, so upgrading from any older build applies
  /// every intermediate step in order. Inspections that have not synced yet
  /// must survive an app update, so dropping and recreating is never an option.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    AppLogger.info('Migrating database $oldVersion -> $newVersion', scope: 'db');
    // Example of the shape future migrations take:
    // if (oldVersion < 2) {
    //   await db.execute('ALTER TABLE inspections ADD COLUMN reviewer_id TEXT');
    // }
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  /// Wipes user data while leaving the seeded templates in place. Used by
  /// tests; a production build would expose this behind a support action.
  Future<void> clearInspectionData() async {
    final db = await database;
    final batch = db.batch();
    batch.delete(Tables.syncQueue);
    batch.delete(Tables.inspectionPhotos);
    batch.delete(Tables.inspectionItems);
    batch.delete(Tables.inspections);
    await batch.commit(noResult: true);
  }

  static const List<String> _schemaV1 = [
    '''
    CREATE TABLE ${Tables.templates} (
      id                TEXT    NOT NULL,
      version           INTEGER NOT NULL,
      name              TEXT    NOT NULL,
      description       TEXT,
      is_default        INTEGER NOT NULL DEFAULT 0,
      is_active         INTEGER NOT NULL DEFAULT 1,
      grading_rules     TEXT    NOT NULL,
      updated_at        TEXT,
      PRIMARY KEY (id, version)
    )
    ''',
    '''
    CREATE TABLE ${Tables.templateCategories} (
      template_id       TEXT    NOT NULL,
      template_version  INTEGER NOT NULL,
      id                TEXT    NOT NULL,
      code              TEXT    NOT NULL,
      title             TEXT    NOT NULL,
      icon_name         TEXT,
      sort_order        INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (template_id, template_version, id),
      FOREIGN KEY (template_id, template_version)
        REFERENCES ${Tables.templates} (id, version) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE TABLE ${Tables.templatePoints} (
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
        REFERENCES ${Tables.templates} (id, version) ON DELETE CASCADE
    )
    ''',
    'CREATE INDEX idx_points_category ON ${Tables.templatePoints} '
        '(template_id, template_version, category_id, sort_order)',
    '''
    CREATE TABLE ${Tables.inspections} (
      id                  TEXT    PRIMARY KEY,
      remote_id           TEXT,
      reference_number    TEXT    NOT NULL UNIQUE,
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
      completed_items     INTEGER NOT NULL DEFAULT 0,
      total_items         INTEGER NOT NULL DEFAULT 0,
      created_at          TEXT    NOT NULL,
      updated_at          TEXT    NOT NULL,
      submitted_at        TEXT,
      sync_status         TEXT    NOT NULL,
      sync_attempts       INTEGER NOT NULL DEFAULT 0,
      last_sync_error     TEXT
    )
    ''',
    'CREATE INDEX idx_inspections_created ON ${Tables.inspections} (created_at DESC)',
    'CREATE INDEX idx_inspections_status ON ${Tables.inspections} (status)',
    'CREATE INDEX idx_inspections_sync ON ${Tables.inspections} (sync_status)',
    'CREATE INDEX idx_inspections_registration ON ${Tables.inspections} (registration_number)',
    '''
    CREATE TABLE ${Tables.inspectionItems} (
      id            TEXT PRIMARY KEY,
      inspection_id TEXT NOT NULL,
      point_id      TEXT NOT NULL,
      status        TEXT NOT NULL,
      comment       TEXT,
      updated_at    TEXT,
      UNIQUE (inspection_id, point_id),
      FOREIGN KEY (inspection_id)
        REFERENCES ${Tables.inspections} (id) ON DELETE CASCADE
    )
    ''',
    'CREATE INDEX idx_items_inspection ON ${Tables.inspectionItems} (inspection_id)',
    '''
    CREATE TABLE ${Tables.inspectionPhotos} (
      id            TEXT    PRIMARY KEY,
      inspection_id TEXT    NOT NULL,
      item_id       TEXT    NOT NULL,
      local_path    TEXT    NOT NULL,
      remote_url    TEXT,
      byte_size     INTEGER NOT NULL DEFAULT 0,
      width         INTEGER,
      height        INTEGER,
      created_at    TEXT    NOT NULL,
      sync_status   TEXT    NOT NULL,
      last_error    TEXT,
      FOREIGN KEY (inspection_id)
        REFERENCES ${Tables.inspections} (id) ON DELETE CASCADE,
      FOREIGN KEY (item_id)
        REFERENCES ${Tables.inspectionItems} (id) ON DELETE CASCADE
    )
    ''',
    'CREATE INDEX idx_photos_item ON ${Tables.inspectionPhotos} (item_id)',
    'CREATE INDEX idx_photos_inspection ON ${Tables.inspectionPhotos} (inspection_id)',
    'CREATE INDEX idx_photos_sync ON ${Tables.inspectionPhotos} (sync_status)',
    '''
    CREATE TABLE ${Tables.syncQueue} (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type     TEXT    NOT NULL,
      entity_id       TEXT    NOT NULL,
      operation       TEXT    NOT NULL,
      payload         TEXT,
      attempts        INTEGER NOT NULL DEFAULT 0,
      next_attempt_at TEXT    NOT NULL,
      last_error      TEXT,
      created_at      TEXT    NOT NULL,
      updated_at      TEXT    NOT NULL,
      UNIQUE (entity_type, entity_id, operation)
    )
    ''',
    'CREATE INDEX idx_queue_ready ON ${Tables.syncQueue} (next_attempt_at)',
  ];
}
