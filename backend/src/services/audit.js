import { all, nowIso, run } from '../db/database.js';

/**
 * Records who changed what.
 *
 * Templates and grading rules decide what an inspection is worth, so a change
 * to them retroactively changes how work is judged. That needs a name against
 * it — an audit trail is the difference between "the scale changed" and
 * "someone changed the scale, on this date, for this reason".
 */
export function recordAudit({ actor, action, entityType, entityId, detail }) {
  run(
    `INSERT INTO audit_log
       (actor_id, actor_name, action, entity_type, entity_id, detail, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    actor?.id ?? null,
    actor?.name ?? 'system',
    action,
    entityType,
    entityId ?? null,
    detail ? JSON.stringify(detail) : null,
    nowIso(),
  );
}

export function listAudit({ limit = 100 } = {}) {
  return all(
    `SELECT id, actor_name, action, entity_type, entity_id, detail, created_at
       FROM audit_log ORDER BY created_at DESC, id DESC LIMIT ?`,
    limit,
  ).map((row) => ({
    id: row.id,
    actorName: row.actor_name,
    action: row.action,
    entityType: row.entity_type,
    entityId: row.entity_id,
    detail: row.detail ? JSON.parse(row.detail) : null,
    createdAt: row.created_at,
  }));
}
