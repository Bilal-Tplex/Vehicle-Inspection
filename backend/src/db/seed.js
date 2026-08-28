import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { config, ROOT } from '../config.js';
import { closeDatabase, get, nowIso, run } from './database.js';
import { generateId, hashPassword } from '../services/security.js';
import { saveTemplateVersion } from '../services/templates.js';

const here = path.dirname(fileURLToPath(import.meta.url));

/**
 * First-run data.
 *
 * The checklist is the same `standard_inspection_v1.json` the mobile app
 * bundles as its offline fallback, so a phone that seeded itself from the asset
 * and a phone that pulled from this server end up on byte-identical
 * definitions — same ids, same version, same grading rules. Without that, an
 * inspection captured offline would reference points the server had never
 * heard of.
 */
const TEMPLATE_FILE = path.join(here, 'standard-template.json');

const ACCOUNTS = [
  {
    name: 'Sara Malik',
    email: 'admin@test.com',
    password: 'admin123',
    role: 'admin',
    branch: 'Head Office',
  },
  {
    name: 'Bilal Ahmed',
    email: 'reviewer@test.com',
    password: 'reviewer123',
    role: 'reviewer',
    branch: 'Head Office',
  },
  {
    // Must match the credentials the mobile app documents, or the app cannot
    // sign in against this backend.
    name: 'Ahmed Tariq',
    email: 'evaluator@test.com',
    password: 'password123',
    role: 'evaluator',
    branch: 'Lahore Central',
  },
];

function seedUsers() {
  const timestamp = nowIso();
  let created = 0;

  for (const account of ACCOUNTS) {
    const existing = get('SELECT id FROM users WHERE email = ?', account.email);
    if (existing) continue;

    run(
      `INSERT INTO users
         (id, name, email, password_hash, role, branch, is_active, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)`,
      generateId('usr'),
      account.name,
      account.email,
      hashPassword(account.password),
      account.role,
      account.branch,
      timestamp,
      timestamp,
    );
    created += 1;
  }
  return created;
}

function seedTemplate() {
  const definition = JSON.parse(fs.readFileSync(TEMPLATE_FILE, 'utf8'));
  const existing = get(
    'SELECT id FROM templates WHERE id = ? AND version = ?',
    definition.id,
    definition.version,
  );
  if (existing) return null;

  const admin = get("SELECT id FROM users WHERE role = 'admin' LIMIT 1");

  return saveTemplateVersion({
    id: definition.id,
    version: definition.version,
    name: definition.name,
    description: definition.description,
    gradingRules: definition.gradingRules,
    categories: definition.categories,
    isDefault: true,
    isPublished: true,
    actorId: admin?.id ?? null,
  });
}

function reset() {
  fs.rmSync(config.db.file, { force: true });
  fs.rmSync(`${config.db.file}-wal`, { force: true });
  fs.rmSync(`${config.db.file}-shm`, { force: true });
  fs.rmSync(config.storage.photos, { recursive: true, force: true });
  console.log('Cleared database and uploaded media.');
}

export function seed({ verbose = true } = {}) {
  const users = seedUsers();
  const template = seedTemplate();

  if (verbose) {
    const pointCount =
      template?.categories.reduce((n, c) => n + c.points.length, 0) ?? 0;
    console.log(`Users seeded:     ${users}`);
    console.log(
      template
        ? `Template seeded:  ${template.name} v${template.version} ` +
            `(${template.categories.length} categories, ${pointCount} points)`
        : 'Template seeded:  already present',
    );
  }
  return { users, template };
}

// Only run when invoked directly, not when imported by the server.
const invokedDirectly =
  process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (invokedDirectly) {
  if (process.argv.includes('--reset')) reset();
  seed();
  console.log('\nSign in to the dashboard at http://localhost:%d', config.port);
  console.log('  admin@test.com    / admin123      (full access)');
  console.log('  reviewer@test.com / reviewer123   (read-only)');
  console.log('\nMobile app credentials:');
  console.log('  evaluator@test.com / password123');
  console.log('\nStorage root: %s', path.relative(ROOT, config.storage.photos));
  closeDatabase();
}
