import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));

/** Project root (one level above `src`). */
export const ROOT = path.resolve(here, '..');

export const config = {
  port: Number(process.env.PORT ?? 4000),

  /** Mounted under a version prefix so a v2 can co-exist later. */
  apiPrefix: '/v1',

  db: {
    file: process.env.DB_FILE ?? path.join(ROOT, 'data', 'inspections.db'),
    schema: path.join(ROOT, 'src', 'db', 'schema.sql'),
  },

  storage: {
    /** Uploaded photos live outside the database, keyed by inspection. */
    photos: path.join(ROOT, 'storage', 'photos'),
    maxUploadBytes: 12 * 1024 * 1024,
    allowedMimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
  },

  auth: {
    sessionTtlDays: 30,
    /** scrypt parameters. Cost is deliberate: logins are rare. */
    scrypt: { keyLength: 64, cost: 16384, blockSize: 8, parallelization: 1 },
  },

  /** Roles allowed to sign in to the dashboard. Evaluators use the app. */
  dashboardRoles: ['admin', 'reviewer'],
};
