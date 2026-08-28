import { config } from '../config.js';
import { get, run, toBool } from '../db/database.js';
import { ApiError } from './errors.js';

/**
 * Bearer-token authentication.
 *
 * Tokens are opaque and stored server-side, so revoking one is a row delete —
 * no waiting for a JWT to expire. Both the mobile app and the dashboard use the
 * same scheme; what differs is the role check applied afterwards.
 */
export function authenticate(req, _res, next) {
  const header = req.get('authorization') ?? '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : null;

  if (!token) return next(ApiError.unauthorized());

  const row = get(
    `SELECT s.token, s.expires_at, u.id, u.name, u.email, u.role, u.branch, u.is_active
       FROM sessions s
       JOIN users u ON u.id = s.user_id
      WHERE s.token = ?`,
    token,
  );

  if (!row) return next(ApiError.unauthorized('Session not recognised'));

  if (new Date(row.expires_at) < new Date()) {
    run('DELETE FROM sessions WHERE token = ?', token);
    return next(ApiError.unauthorized('Session has expired'));
  }

  if (!toBool(row.is_active)) {
    return next(ApiError.forbidden('This account has been deactivated'));
  }

  req.user = {
    id: row.id,
    name: row.name,
    email: row.email,
    role: row.role,
    branch: row.branch,
  };
  req.token = token;
  next();
}

/** Restricts a route to the given roles. */
export const requireRole =
  (...roles) =>
  (req, _res, next) => {
    if (!req.user) return next(ApiError.unauthorized());
    if (!roles.includes(req.user.role)) {
      return next(
        ApiError.forbidden(`This action requires: ${roles.join(' or ')}`),
      );
    }
    next();
  };

/** Dashboard routes: admins and reviewers only. Evaluators use the app. */
export const requireDashboard = requireRole(...config.dashboardRoles);

/** Write actions on templates, grading rules and accounts. */
export const requireAdmin = requireRole('admin');
