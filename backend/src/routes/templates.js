import { Router } from 'express';

import { get, run, toBool } from '../db/database.js';
import { authenticate, requireAdmin, requireDashboard } from '../middleware/auth.js';
import { ApiError, asyncRoute } from '../middleware/errors.js';
import { recordAudit } from '../services/audit.js';
import { generateId } from '../services/security.js';
import {
  getTemplate,
  listTemplates,
  listVersions,
  nextVersion,
  saveTemplateVersion,
} from '../services/templates.js';

export const templateRouter = Router();
export const adminTemplateRouter = Router();

// ---------------------------------------------------------------------------
// Mobile
// ---------------------------------------------------------------------------

/**
 * Published templates, in the shape the app parses.
 *
 * The app calls this on every sync and writes back anything whose version it
 * has not seen, so publishing a revision here is how a checklist change reaches
 * the field — no app release involved.
 */
templateRouter.get(
  '/',
  authenticate,
  asyncRoute((_req, res) => {
    res.json({ templates: listTemplates({ publishedOnly: true }) });
  }),
);

// ---------------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------------

adminTemplateRouter.use(authenticate, requireDashboard);

adminTemplateRouter.get(
  '/',
  asyncRoute((_req, res) => {
    const templates = listTemplates().map((template) => ({
      ...template,
      pointCount: template.categories.reduce((n, c) => n + c.points.length, 0),
      versions: listVersions(template.id),
    }));
    res.json({ templates });
  }),
);

adminTemplateRouter.get(
  '/:id',
  asyncRoute((req, res) => {
    const version = req.query.version ? Number(req.query.version) : undefined;
    const template = getTemplate(req.params.id, version);
    if (!template) throw ApiError.notFound('Template not found');
    res.json({ template, versions: listVersions(req.params.id) });
  }),
);

/** Validates the payload a dashboard save sends. */
function readTemplateBody(body) {
  const name = String(body?.name ?? '').trim();
  if (!name) throw ApiError.unprocessable('Template name is required.');

  const categories = Array.isArray(body?.categories) ? body.categories : [];
  if (categories.length === 0) {
    throw ApiError.unprocessable('A template needs at least one category.');
  }

  const seenPointIds = new Set();
  for (const category of categories) {
    if (!String(category.title ?? '').trim()) {
      throw ApiError.unprocessable('Every category needs a title.');
    }
    for (const point of category.points ?? []) {
      if (!String(point.title ?? '').trim()) {
        throw ApiError.unprocessable(
          `Every point in "${category.title}" needs a title.`,
        );
      }
      // Answers are stored against point ids, so a duplicate would make an
      // inspection ambiguous.
      if (seenPointIds.has(point.id)) {
        throw ApiError.unprocessable(`Duplicate point id: ${point.id}`);
      }
      seenPointIds.add(point.id);
    }
  }

  return {
    name,
    description: body?.description ?? null,
    gradingRules: body?.gradingRules,
    categories,
  };
}

adminTemplateRouter.post(
  '/',
  requireAdmin,
  asyncRoute((req, res) => {
    const body = readTemplateBody(req.body);
    const id = String(req.body?.id ?? '').trim() || generateId('tpl');

    if (get('SELECT id FROM templates WHERE id = ? LIMIT 1', id)) {
      throw ApiError.unprocessable(`A template with id "${id}" already exists.`);
    }

    const template = saveTemplateVersion({
      ...body,
      id,
      version: 1,
      isPublished: false,
      actorId: req.user.id,
    });

    recordAudit({
      actor: req.user,
      action: 'template.create',
      entityType: 'template',
      entityId: id,
      detail: { version: 1, name: template.name },
    });

    res.status(201).json({ template });
  }),
);

/**
 * Saves an edit.
 *
 * A published version is immutable — inspections in the field reference it — so
 * editing one opens the next version as a draft instead of mutating rows. An
 * unpublished draft is overwritten in place.
 */
adminTemplateRouter.put(
  '/:id',
  requireAdmin,
  asyncRoute((req, res) => {
    const body = readTemplateBody(req.body);
    const { id } = req.params;

    const latest = get(
      'SELECT version, is_published FROM templates WHERE id = ? ORDER BY version DESC LIMIT 1',
      id,
    );
    if (!latest) throw ApiError.notFound('Template not found');

    const isDraft = !toBool(latest.is_published);
    const version = isDraft ? latest.version : nextVersion(id);

    const template = saveTemplateVersion({
      ...body,
      id,
      version,
      isPublished: false,
      actorId: req.user.id,
    });

    recordAudit({
      actor: req.user,
      action: isDraft ? 'template.update_draft' : 'template.new_version',
      entityType: 'template',
      entityId: id,
      detail: { version, name: template.name },
    });

    res.json({ template, createdNewVersion: !isDraft });
  }),
);

adminTemplateRouter.post(
  '/:id/publish',
  requireAdmin,
  asyncRoute((req, res) => {
    const { id } = req.params;
    const version = Number(req.body?.version);
    const makeDefault = req.body?.makeDefault !== false;

    const existing = get(
      'SELECT version FROM templates WHERE id = ? AND version = ?',
      id,
      version,
    );
    if (!existing) throw ApiError.notFound('That template version does not exist');

    run(
      'UPDATE templates SET is_published = 1, updated_at = ? WHERE id = ? AND version = ?',
      new Date().toISOString(),
      id,
      version,
    );

    if (makeDefault) {
      run('UPDATE templates SET is_default = 0');
      run('UPDATE templates SET is_default = 1 WHERE id = ? AND version = ?', id, version);
    }

    recordAudit({
      actor: req.user,
      action: 'template.publish',
      entityType: 'template',
      entityId: id,
      detail: { version, madeDefault: makeDefault },
    });

    res.json({ template: getTemplate(id, version) });
  }),
);

adminTemplateRouter.delete(
  '/:id/versions/:version',
  requireAdmin,
  asyncRoute((req, res) => {
    const { id } = req.params;
    const version = Number(req.params.version);

    const row = get(
      'SELECT is_published FROM templates WHERE id = ? AND version = ?',
      id,
      version,
    );
    if (!row) throw ApiError.notFound('That template version does not exist');

    // Published versions are referenced by inspections; deleting one would
    // orphan their answers.
    if (toBool(row.is_published)) {
      throw ApiError.unprocessable(
        'Published versions cannot be deleted. Publish a newer version instead.',
      );
    }

    run('DELETE FROM templates WHERE id = ? AND version = ?', id, version);
    recordAudit({
      actor: req.user,
      action: 'template.delete_draft',
      entityType: 'template',
      entityId: id,
      detail: { version },
    });

    res.json({ ok: true });
  }),
);
