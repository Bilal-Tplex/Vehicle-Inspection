import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import path from 'node:path';

import { config } from '../config.js';

/**
 * The SQLite connection.
 *
 * `node:sqlite` ships with Node 22, so there is no native module to compile and
 * no database server to install — `npm install && npm start` is the whole
 * setup. The trade-off is a single-writer database, which is the right shape
 * for an internal dashboard and would be swapped for Postgres before this
 * carried real traffic.
 */
let db;

export function getDatabase() {
  if (db) return db;

  fs.mkdirSync(path.dirname(config.db.file), { recursive: true });
  fs.mkdirSync(config.storage.photos, { recursive: true });

  db = new DatabaseSync(config.db.file);
  // Foreign keys are off by default in SQLite; without this the cascade
  // deletes in the schema silently do nothing.
  db.exec('PRAGMA foreign_keys = ON');
  // WAL keeps dashboard reads from blocking while the app is submitting.
  db.exec('PRAGMA journal_mode = WAL');
  db.exec(fs.readFileSync(config.db.schema, 'utf8'));

  return db;
}

/** Runs `fn` inside a transaction, rolling back if it throws. */
export function transaction(fn) {
  const database = getDatabase();
  database.exec('BEGIN');
  try {
    const result = fn(database);
    database.exec('COMMIT');
    return result;
  } catch (error) {
    database.exec('ROLLBACK');
    throw error;
  }
}

export const all = (sql, ...params) =>
  getDatabase().prepare(sql).all(...params);

export const get = (sql, ...params) =>
  getDatabase().prepare(sql).get(...params);

export const run = (sql, ...params) =>
  getDatabase().prepare(sql).run(...params);

export const nowIso = () => new Date().toISOString();

/** SQLite has no boolean type; normalise the 0/1 columns on the way out. */
export const toBool = (value) => value === 1 || value === true;

export function closeDatabase() {
  db?.close();
  db = undefined;
}
