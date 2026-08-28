import { all, get, nowIso, run, toBool, transaction } from '../db/database.js';
import { DEFAULT_GRADING_RULES } from './grading.js';

/**
 * Template storage and serialisation.
 *
 * The JSON this produces is exactly what the mobile app's
 * `InspectionTemplate.fromJson` consumes — same keys, same casing, same nesting.
 * That is not a coincidence to be maintained by hand: the app was written
 * against this shape from the start, which is why pointing it at this server
 * needed no parsing changes at all.
 */

function parseRules(raw) {
  if (!raw) return DEFAULT_GRADING_RULES;
  try {
    return JSON.parse(raw);
  } catch {
    // A corrupt rules column must not make the template unusable.
    return DEFAULT_GRADING_RULES;
  }
}

function pointToJson(row) {
  return {
    id: row.id,
    categoryId: row.category_id,
    code: row.code,
    title: row.title,
    description: row.description ?? null,
    isRequired: toBool(row.is_required),
    allowsNotApplicable: toBool(row.allows_na),
    requiresPhotoOnFail: toBool(row.requires_photo_on_fail),
    maxPhotos: row.max_photos,
    weight: row.weight,
    sortOrder: row.sort_order,
  };
}

/** Assembles one template from its three tables in two queries. */
export function getTemplate(id, version) {
  const header = version
    ? get('SELECT * FROM templates WHERE id = ? AND version = ?', id, version)
    : get(
        'SELECT * FROM templates WHERE id = ? ORDER BY version DESC LIMIT 1',
        id,
      );
  if (!header) return null;

  const categoryRows = all(
    `SELECT * FROM template_categories
      WHERE template_id = ? AND template_version = ?
      ORDER BY sort_order ASC`,
    header.id,
    header.version,
  );
  const pointRows = all(
    `SELECT * FROM template_points
      WHERE template_id = ? AND template_version = ?
      ORDER BY sort_order ASC`,
    header.id,
    header.version,
  );

  const pointsByCategory = new Map();
  for (const row of pointRows) {
    const list = pointsByCategory.get(row.category_id) ?? [];
    list.push(pointToJson(row));
    pointsByCategory.set(row.category_id, list);
  }

  return {
    id: header.id,
    name: header.name,
    version: header.version,
    description: header.description ?? null,
    isDefault: toBool(header.is_default),
    isPublished: toBool(header.is_published),
    updatedAt: header.updated_at,
    createdAt: header.created_at,
    gradingRules: parseRules(header.grading_rules),
    categories: categoryRows.map((row) => ({
      id: row.id,
      code: row.code,
      title: row.title,
      iconName: row.icon_name ?? null,
      sortOrder: row.sort_order,
      points: pointsByCategory.get(row.id) ?? [],
    })),
  };
}

/** Newest version of every template id. */
export function listTemplates({ publishedOnly = false } = {}) {
  const rows = all(
    `SELECT t.id, MAX(t.version) AS version
       FROM templates t
      ${publishedOnly ? 'WHERE t.is_published = 1' : ''}
      GROUP BY t.id`,
  );
  return rows
    .map((row) => getTemplate(row.id, row.version))
    .filter(Boolean)
    .sort((a, b) => Number(b.isDefault) - Number(a.isDefault));
}

/** Every stored revision of one template id, newest first. */
export function listVersions(id) {
  return all(
    `SELECT version, is_published, is_default, updated_at, created_at
       FROM templates WHERE id = ? ORDER BY version DESC`,
    id,
  ).map((row) => ({
    version: row.version,
    isPublished: toBool(row.is_published),
    isDefault: toBool(row.is_default),
    updatedAt: row.updated_at,
    createdAt: row.created_at,
  }));
}

/** Template the mobile app should use for new inspections. */
export function getActiveTemplate() {
  const row = get(
    `SELECT id, version FROM templates
      WHERE is_published = 1
      ORDER BY is_default DESC, version DESC
      LIMIT 1`,
  );
  return row ? getTemplate(row.id, row.version) : null;
}

/**
 * Writes a template revision.
 *
 * Versions are immutable once published, so an edit lands as a new version
 * rather than mutating rows an existing inspection points at. Category and
 * point order is taken from array position, which is what makes drag-to-reorder
 * in the dashboard a plain array move.
 */
export function saveTemplateVersion({
  id,
  version,
  name,
  description,
  gradingRules,
  categories,
  isDefault = false,
  isPublished = false,
  actorId = null,
}) {
  const timestamp = nowIso();

  return transaction(() => {
    if (isDefault) {
      run('UPDATE templates SET is_default = 0 WHERE id != ? OR version != ?', id, version);
    }

    const existing = get(
      'SELECT created_at FROM templates WHERE id = ? AND version = ?',
      id,
      version,
    );

    run(
      `INSERT OR REPLACE INTO templates
         (id, version, name, description, is_default, is_published,
          grading_rules, created_by, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      id,
      version,
      name,
      description ?? null,
      isDefault ? 1 : 0,
      isPublished ? 1 : 0,
      JSON.stringify(gradingRules ?? DEFAULT_GRADING_RULES),
      actorId,
      existing?.created_at ?? timestamp,
      timestamp,
    );

    // Replace the definition wholesale so points an admin removed disappear.
    run('DELETE FROM template_categories WHERE template_id = ? AND template_version = ?', id, version);
    run('DELETE FROM template_points WHERE template_id = ? AND template_version = ?', id, version);

    categories.forEach((category, categoryIndex) => {
      run(
        `INSERT INTO template_categories
           (template_id, template_version, id, code, title, icon_name, sort_order)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        id,
        version,
        category.id,
        category.code,
        category.title,
        category.iconName ?? null,
        categoryIndex + 1,
      );

      (category.points ?? []).forEach((point, pointIndex) => {
        run(
          `INSERT INTO template_points
             (template_id, template_version, id, category_id, code, title,
              description, is_required, allows_na, requires_photo_on_fail,
              max_photos, weight, sort_order)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          id,
          version,
          point.id,
          category.id,
          point.code,
          point.title,
          point.description ?? null,
          point.isRequired === false ? 0 : 1,
          point.allowsNotApplicable === false ? 0 : 1,
          point.requiresPhotoOnFail ? 1 : 0,
          Number(point.maxPhotos ?? 3),
          Number(point.weight ?? 1),
          pointIndex + 1,
        );
      });
    });

    return getTemplate(id, version);
  });
}

export function nextVersion(id) {
  const row = get('SELECT MAX(version) AS v FROM templates WHERE id = ?', id);
  return (row?.v ?? 0) + 1;
}

/** Flat point lookup, used when grading a submission. */
export function pointWeightMap(templateId, templateVersion) {
  const rows = all(
    'SELECT id, weight FROM template_points WHERE template_id = ? AND template_version = ?',
    templateId,
    templateVersion,
  );
  return new Map(rows.map((row) => [row.id, row.weight]));
}
