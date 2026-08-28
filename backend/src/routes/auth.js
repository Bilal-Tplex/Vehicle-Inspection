import { Router } from 'express';

import { config } from '../config.js';
import { get, nowIso, run, toBool } from '../db/database.js';
import { authenticate } from '../middleware/auth.js';
import { ApiError, asyncRoute } from '../middleware/errors.js';
import { generateToken, verifyPassword } from '../services/security.js';

export const authRouter = Router();

const publicUser = (row) => ({
  id: row.id,
  name: row.name,
  email: row.email,
  role: row.role,
  branch: row.branch ?? null,
});

/**
 * One login endpoint for both clients.
 *
 * The response carries the profile under `evaluator` because that is the key
 * the mobile app already parses, and repeats it under `user` for the dashboard.
 * Two names for one object is a small price for not versioning the endpoint.
 */
authRouter.post(
  '/login',
  asyncRoute((req, res) => {
    const email = String(req.body?.email ?? '').trim().toLowerCase();
    const password = String(req.body?.password ?? '');

    if (!email || !password) {
      throw ApiError.badRequest('Email and password are required.');
    }

    const row = get('SELECT * FROM users WHERE email = ?', email);

    // Same message and shape whether the address is unknown or the password is
    // wrong, so the endpoint cannot be used to enumerate accounts.
    if (!row || !verifyPassword(password, row.password_hash)) {
      throw ApiError.unauthorized('Invalid email or password.');
    }
    if (!toBool(row.is_active)) {
      throw ApiError.forbidden('This account has been deactivated.');
    }

    const token = generateToken();
    const issuedAt = new Date();
    const expiresAt = new Date(
      issuedAt.getTime() + config.auth.sessionTtlDays * 86_400_000,
    );

    run(
      'INSERT INTO sessions (token, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)',
      token,
      row.id,
      issuedAt.toISOString(),
      expiresAt.toISOString(),
    );

    res.json({
      accessToken: token,
      expiresIn: config.auth.sessionTtlDays * 86_400,
      evaluator: publicUser(row),
      user: publicUser(row),
    });
  }),
);

authRouter.get(
  '/me',
  authenticate,
  asyncRoute((req, res) => res.json({ user: req.user })),
);

authRouter.post(
  '/logout',
  authenticate,
  asyncRoute((req, res) => {
    run('DELETE FROM sessions WHERE token = ?', req.token);
    res.json({ ok: true, loggedOutAt: nowIso() });
  }),
);
