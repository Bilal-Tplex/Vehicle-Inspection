import { Router } from 'express';

import { all, get, nowIso, run, toBool } from '../db/database.js';
import { authenticate, requireAdmin, requireDashboard } from '../middleware/auth.js';
import { ApiError, asyncRoute } from '../middleware/errors.js';
import { recordAudit } from '../services/audit.js';
import { generateId, hashPassword } from '../services/security.js';

export const userRouter = Router();

userRouter.use(authenticate, requireDashboard);

const ROLES = ['admin', 'reviewer', 'evaluator'];

const toJson = (row) => ({
  id: row.id,
  name: row.name,
  email: row.email,
  role: row.role,
  branch: row.branch ?? null,
  isActive: toBool(row.is_active),
  createdAt: row.created_at,
  inspectionCount: row.inspection_count ?? 0,
  lastSubmittedAt: row.last_submitted_at ?? null,
});

/** Accounts, with each evaluator's throughput folded in by SQL. */
userRouter.get(
  '/',
  asyncRoute((_req, res) => {
    const rows = all(
      `SELECT u.*,
              (SELECT COUNT(*) FROM inspections i WHERE i.evaluator_id = u.id)
                AS inspection_count,
              (SELECT MAX(i.submitted_at) FROM inspections i WHERE i.evaluator_id = u.id)
                AS last_submitted_at
         FROM users u
        ORDER BY CASE u.role WHEN 'admin' THEN 0 WHEN 'reviewer' THEN 1 ELSE 2 END,
                 u.name ASC`,
    );
    res.json({ users: rows.map(toJson) });
  }),
);

userRouter.post(
  '/',
  requireAdmin,
  asyncRoute((req, res) => {
    const name = String(req.body?.name ?? '').trim();
    const email = String(req.body?.email ?? '').trim().toLowerCase();
    const password = String(req.body?.password ?? '');
    const role = String(req.body?.role ?? 'evaluator');

    if (!name) throw ApiError.unprocessable('Name is required.');
    if (!/^[\w.+-]+@[\w-]+\.[\w.-]+$/.test(email)) {
      throw ApiError.unprocessable('A valid email address is required.');
    }
    if (password.length < 6) {
      throw ApiError.unprocessable('Password must be at least 6 characters.');
    }
    if (!ROLES.includes(role)) {
      throw ApiError.unprocessable(`Role must be one of: ${ROLES.join(', ')}`);
    }
    if (get('SELECT id FROM users WHERE email = ?', email)) {
      throw ApiError.unprocessable('That email address is already registered.');
    }

    const id = generateId('usr');
    const timestamp = nowIso();
    run(
      `INSERT INTO users
         (id, name, email, password_hash, role, branch, is_active, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)`,
      id,
      name,
      email,
      hashPassword(password),
      role,
      req.body?.branch ?? null,
      timestamp,
      timestamp,
    );

    recordAudit({
      actor: req.user,
      action: 'user.create',
      entityType: 'user',
      entityId: id,
      detail: { email, role },
    });

    res.status(201).json({ user: toJson(get('SELECT * FROM users WHERE id = ?', id)) });
  }),
);

userRouter.patch(
  '/:id',
  requireAdmin,
  asyncRoute((req, res) => {
    const existing = get('SELECT * FROM users WHERE id = ?', req.params.id);
    if (!existing) throw ApiError.notFound('User not found');

    const role = req.body?.role ?? existing.role;
    if (!ROLES.includes(role)) {
      throw ApiError.unprocessable(`Role must be one of: ${ROLES.join(', ')}`);
    }

    const isActive =
      req.body?.isActive === undefined
        ? toBool(existing.is_active)
        : Boolean(req.body.isActive);

    // Locking every admin out of the dashboard would need database access to
    // undo, so the last active one cannot be demoted or disabled.
    const losingAdmin =
      existing.role === 'admin' && (role !== 'admin' || !isActive);
    if (losingAdmin) {
      const remaining = get(
        "SELECT COUNT(*) AS n FROM users WHERE role = 'admin' AND is_active = 1 AND id != ?",
        existing.id,
      );
      if ((remaining?.n ?? 0) === 0) {
        throw ApiError.unprocessable(
          'This is the last active admin. Promote another account first.',
        );
      }
    }

    run(
      `UPDATE users SET name = ?, role = ?, branch = ?, is_active = ?, updated_at = ?
        WHERE id = ?`,
      String(req.body?.name ?? existing.name).trim(),
      role,
      req.body?.branch ?? existing.branch,
      isActive ? 1 : 0,
      nowIso(),
      existing.id,
    );

    // Disabling an account should take effect now, not when its token lapses.
    if (!isActive) run('DELETE FROM sessions WHERE user_id = ?', existing.id);

    recordAudit({
      actor: req.user,
      action: 'user.update',
      entityType: 'user',
      entityId: existing.id,
      detail: { role, isActive },
    });

    res.json({ user: toJson(get('SELECT * FROM users WHERE id = ?', existing.id)) });
  }),
);

userRouter.post(
  '/:id/password',
  requireAdmin,
  asyncRoute((req, res) => {
    const password = String(req.body?.password ?? '');
    if (password.length < 6) {
      throw ApiError.unprocessable('Password must be at least 6 characters.');
    }

    const existing = get('SELECT id, email FROM users WHERE id = ?', req.params.id);
    if (!existing) throw ApiError.notFound('User not found');

    run(
      'UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?',
      hashPassword(password),
      nowIso(),
      existing.id,
    );
    // Force every device to sign in again with the new password.
    run('DELETE FROM sessions WHERE user_id = ?', existing.id);

    recordAudit({
      actor: req.user,
      action: 'user.reset_password',
      entityType: 'user',
      entityId: existing.id,
      detail: { email: existing.email },
    });

    res.json({ ok: true });
  }),
);
