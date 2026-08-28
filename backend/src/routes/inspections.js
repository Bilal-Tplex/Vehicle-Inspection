import fs from 'node:fs';
import path from 'node:path';

import { Router } from 'express';
import multer from 'multer';

import { config } from '../config.js';
import { all, get, nowIso, run, transaction } from '../db/database.js';
import { authenticate, requireDashboard } from '../middleware/auth.js';
import { ApiError, asyncRoute } from '../middleware/errors.js';
import { recordAudit } from '../services/audit.js';
import { grade, reconcile } from '../services/grading.js';
import { generateId } from '../services/security.js';
import { getTemplate, pointWeightMap } from '../services/templates.js';

export const inspectionRouter = Router();
export const adminInspectionRouter = Router();
export const mediaRouter = Router();

// ---------------------------------------------------------------------------
// Uploads
// ---------------------------------------------------------------------------

const upload = multer({
  storage: multer.diskStorage({
    destination(req, _file, cb) {
      const dir = path.join(config.storage.photos, req.params.id);
      fs.mkdirSync(dir, { recursive: true });
      cb(null, dir);
    },
    filename(req, file, cb) {
      // Named by the photo id the phone generated, so a retried upload
      // overwrites rather than duplicating.
      const photoId = req.body?.photoId ?? generateId('pho');
      const extension = path.extname(file.originalname) || '.jpg';
      cb(null, `${photoId}${extension}`);
    },
  }),
  limits: { fileSize: config.storage.maxUploadBytes },
  fileFilter(_req, file, cb) {
    if (!config.storage.allowedMimeTypes.includes(file.mimetype)) {
      return cb(ApiError.unprocessable(`Unsupported file type: ${file.mimetype}`));
    }
    cb(null, true);
  },
});

// ---------------------------------------------------------------------------
// Mobile
// ---------------------------------------------------------------------------

/**
 * Accepts a submitted inspection.
 *
 * Idempotent on the id the phone generated: a retry after a lost response
 * returns the original server id instead of creating a second record. That is
 * what makes the client's "retry until it sticks" behaviour safe.
 */
inspectionRouter.post(
  '/',
  authenticate,
  asyncRoute((req, res) => {
    const payload = req.body ?? {};
    const localId = String(payload.id ?? '').trim();

    if (!localId) throw ApiError.unprocessable('Missing inspection id.');
    if (!Array.isArray(payload.items) || payload.items.length === 0) {
      throw ApiError.unprocessable('An inspection must include its items.');
    }

    const existing = get('SELECT id FROM inspections WHERE local_id = ?', localId);
    if (existing) {
      return res.json({ id: existing.id, status: 'accepted', duplicate: true });
    }

    const templateId = String(payload.templateId ?? '');
    const templateVersion = Number(payload.templateVersion ?? 0);
    const template = getTemplate(templateId, templateVersion);
    if (!template) {
      throw ApiError.unprocessable(
        `Unknown template ${templateId} v${templateVersion}.`,
      );
    }

    // Regrade from the answers rather than trusting the client's numbers.
    const weights = pointWeightMap(templateId, templateVersion);
    const computed = grade(
      payload.items.map((item) => ({
        status: item.status,
        weight: weights.get(item.pointId) ?? 1,
      })),
      template.gradingRules,
    );
    const agreement = reconcile(payload, computed);

    const vehicle = payload.vehicle ?? {};
    const remoteId = generateId('ins');
    const receivedAt = nowIso();

    transaction(() => {
      run(
        `INSERT INTO inspections
           (id, local_id, reference_number, template_id, template_version,
            evaluator_id, evaluator_name, registration_number, make, model,
            manufacturing_year, vin, mileage_km, status, score_percentage,
            grade_code, obtained_points, max_points, total_items,
            completed_items, created_at, submitted_at, received_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        remoteId,
        localId,
        payload.referenceNumber ?? remoteId,
        templateId,
        templateVersion,
        // Identity comes from the token, never from the payload. A client must
        // not be able to attribute an inspection to another evaluator, and it
        // also keeps reporting from splitting one person across two ids.
        req.user.id,
        req.user.name,
        String(vehicle.registrationNumber ?? '').toUpperCase(),
        vehicle.make ?? '',
        vehicle.model ?? '',
        Number(vehicle.manufacturingYear ?? 0),
        String(vehicle.vin ?? '').toUpperCase(),
        Number(vehicle.mileageKm ?? 0),
        payload.status ?? 'submitted',
        computed.percentage,
        computed.gradeCode,
        computed.obtainedPoints,
        computed.maxPoints,
        computed.totalItems,
        computed.totalItems - computed.pendingCount,
        payload.createdAt ?? receivedAt,
        payload.submittedAt ?? receivedAt,
        receivedAt,
      );

      for (const item of payload.items) {
        run(
          `INSERT INTO inspection_items
             (id, inspection_id, point_id, status, comment, updated_at)
           VALUES (?, ?, ?, ?, ?, ?)`,
          item.id ?? generateId('itm'),
          remoteId,
          item.pointId,
          item.status ?? 'pending',
          item.comment ?? null,
          item.updatedAt ?? null,
        );
      }
    });

    if (!agreement.agrees) {
      // Not an error: the server's number wins and is stored, but a mismatch
      // means the two grading implementations have drifted and someone should
      // look at it.
      console.warn(
        `Grade mismatch on ${localId}:`,
        JSON.stringify(agreement),
      );
      recordAudit({
        actor: { id: req.user.id, name: req.user.name },
        action: 'inspection.grade_mismatch',
        entityType: 'inspection',
        entityId: remoteId,
        detail: agreement,
      });
    }

    recordAudit({
      actor: { id: req.user.id, name: req.user.name },
      action: 'inspection.submit',
      entityType: 'inspection',
      entityId: remoteId,
      detail: {
        reference: payload.referenceNumber,
        grade: computed.gradeCode,
        score: computed.percentage,
      },
    });

    res.status(201).json({ id: remoteId, status: 'accepted', duplicate: false });
  }),
);

/** Receives one photo. Addressed by the server id the submit call returned. */
inspectionRouter.post(
  '/:id/photos',
  authenticate,
  upload.single('file'),
  asyncRoute((req, res) => {
    const inspection = get('SELECT id FROM inspections WHERE id = ?', req.params.id);
    if (!inspection) {
      if (req.file) fs.rmSync(req.file.path, { force: true });
      throw ApiError.unprocessable('Unknown inspection for this photo.');
    }
    if (!req.file) throw ApiError.unprocessable('No file was uploaded.');

    const photoId = req.body?.photoId ?? generateId('pho');
    const relativePath = path
      .relative(config.storage.photos, req.file.path)
      .split(path.sep)
      .join('/');

    run(
      `INSERT OR REPLACE INTO inspection_photos
         (id, inspection_id, item_id, file_path, byte_size, content_type, uploaded_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      photoId,
      inspection.id,
      req.body?.itemId ?? '',
      relativePath,
      req.file.size,
      req.file.mimetype,
      nowIso(),
    );

    const url = `${req.protocol}://${req.get('host')}${config.apiPrefix}/media/${photoId}`;
    res.status(201).json({ id: photoId, url, bytes: req.file.size });
  }),
);

// ---------------------------------------------------------------------------
// Media
// ---------------------------------------------------------------------------

/** Streams a stored photo. Authenticated: inspection media is not public. */
mediaRouter.get(
  '/:photoId',
  authenticate,
  asyncRoute((req, res) => {
    const row = get(
      'SELECT file_path, content_type FROM inspection_photos WHERE id = ?',
      req.params.photoId,
    );
    if (!row) throw ApiError.notFound('Photo not found');

    const absolute = path.join(config.storage.photos, row.file_path);
    // Defence against a crafted file_path escaping the storage root.
    if (!absolute.startsWith(config.storage.photos)) {
      throw ApiError.forbidden('Invalid media path');
    }
    if (!fs.existsSync(absolute)) throw ApiError.notFound('Photo file is missing');

    res.type(row.content_type ?? 'image/jpeg');
    res.sendFile(absolute);
  }),
);

// ---------------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------------

adminInspectionRouter.use(authenticate, requireDashboard);

adminInspectionRouter.get(
  '/',
  asyncRoute((req, res) => {
    const conditions = [];
    const params = [];

    const search = String(req.query.search ?? '').trim();
    if (search) {
      conditions.push(
        `(i.registration_number LIKE ? OR i.make LIKE ? OR i.model LIKE ?
          OR i.reference_number LIKE ? OR i.vin LIKE ? OR i.evaluator_name LIKE ?)`,
      );
      params.push(...Array(6).fill(`%${search.toUpperCase()}%`));
    }
    if (req.query.grade) {
      conditions.push('i.grade_code = ?');
      params.push(String(req.query.grade));
    }
    if (req.query.review) {
      conditions.push('i.review_status = ?');
      params.push(String(req.query.review));
    }
    if (req.query.evaluatorId) {
      conditions.push('i.evaluator_id = ?');
      params.push(String(req.query.evaluatorId));
    }

    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    const limit = Math.min(Number(req.query.limit ?? 50), 200);
    const offset = Math.max(Number(req.query.offset ?? 0), 0);

    const rows = all(
      `SELECT i.*,
              (SELECT COUNT(*) FROM inspection_photos p WHERE p.inspection_id = i.id)
                AS photo_count
         FROM inspections i
         ${where}
        ORDER BY i.received_at DESC
        LIMIT ? OFFSET ?`,
      ...params,
      limit,
      offset,
    );

    const total = get(
      `SELECT COUNT(*) AS n FROM inspections i ${where}`,
      ...params,
    );

    res.json({
      inspections: rows.map(summaryFromRow),
      total: total?.n ?? 0,
      limit,
      offset,
    });
  }),
);

function summaryFromRow(row) {
  return {
    id: row.id,
    localId: row.local_id,
    referenceNumber: row.reference_number,
    registrationNumber: row.registration_number,
    vehicleName: `${row.make} ${row.model}`.trim(),
    make: row.make,
    model: row.model,
    manufacturingYear: row.manufacturing_year,
    vin: row.vin,
    mileageKm: row.mileage_km,
    evaluatorId: row.evaluator_id,
    evaluatorName: row.evaluator_name,
    scorePercentage: row.score_percentage,
    gradeCode: row.grade_code,
    obtainedPoints: row.obtained_points,
    maxPoints: row.max_points,
    totalItems: row.total_items,
    completedItems: row.completed_items,
    reviewStatus: row.review_status,
    reviewNote: row.review_note ?? null,
    reviewedAt: row.reviewed_at ?? null,
    photoCount: row.photo_count ?? 0,
    submittedAt: row.submitted_at,
    receivedAt: row.received_at,
    templateId: row.template_id,
    templateVersion: row.template_version,
  };
}

/**
 * Full detail, with each answer resolved against the template revision the
 * inspection was captured with — so a point renamed in a later version still
 * shows the wording the evaluator actually saw.
 */
adminInspectionRouter.get(
  '/:id',
  asyncRoute((req, res) => {
    const row = get(
      `SELECT i.*, (SELECT COUNT(*) FROM inspection_photos p
                     WHERE p.inspection_id = i.id) AS photo_count
         FROM inspections i WHERE i.id = ?`,
      req.params.id,
    );
    if (!row) throw ApiError.notFound('Inspection not found');

    const template = getTemplate(row.template_id, row.template_version);
    const pointIndex = new Map();
    for (const category of template?.categories ?? []) {
      for (const point of category.points) {
        pointIndex.set(point.id, { point, category });
      }
    }

    const photos = all(
      'SELECT * FROM inspection_photos WHERE inspection_id = ? ORDER BY uploaded_at ASC',
      row.id,
    );
    const photosByItem = new Map();
    for (const photo of photos) {
      const list = photosByItem.get(photo.item_id) ?? [];
      list.push({
        id: photo.id,
        itemId: photo.item_id,
        byteSize: photo.byte_size,
        contentType: photo.content_type,
        uploadedAt: photo.uploaded_at,
        url: `${config.apiPrefix}/media/${photo.id}`,
      });
      photosByItem.set(photo.item_id, list);
    }

    const items = all(
      'SELECT * FROM inspection_items WHERE inspection_id = ?',
      row.id,
    ).map((item) => {
      const resolved = pointIndex.get(item.point_id);
      return {
        id: item.id,
        pointId: item.point_id,
        status: item.status,
        comment: item.comment ?? null,
        updatedAt: item.updated_at ?? null,
        photos: photosByItem.get(item.id) ?? [],
        code: resolved?.point.code ?? item.point_id,
        title: resolved?.point.title ?? 'Removed from template',
        description: resolved?.point.description ?? null,
        isRequired: resolved?.point.isRequired ?? true,
        weight: resolved?.point.weight ?? 1,
        categoryId: resolved?.category.id ?? 'unknown',
        categoryTitle: resolved?.category.title ?? 'Unknown category',
        categorySortOrder: resolved?.category.sortOrder ?? 999,
        sortOrder: resolved?.point.sortOrder ?? 999,
      };
    });

    items.sort(
      (a, b) =>
        a.categorySortOrder - b.categorySortOrder || a.sortOrder - b.sortOrder,
    );

    res.json({
      inspection: summaryFromRow(row),
      items,
      photos: photos.map((photo) => ({
        id: photo.id,
        itemId: photo.item_id,
        url: `${config.apiPrefix}/media/${photo.id}`,
        byteSize: photo.byte_size,
        uploadedAt: photo.uploaded_at,
      })),
      template: template
        ? { id: template.id, name: template.name, version: template.version }
        : null,
      gradingRules: template?.gradingRules ?? null,
    });
  }),
);

/** Reviewer sign-off. */
adminInspectionRouter.patch(
  '/:id/review',
  asyncRoute((req, res) => {
    const status = String(req.body?.reviewStatus ?? '');
    if (!['pending', 'approved', 'rejected'].includes(status)) {
      throw ApiError.unprocessable('reviewStatus must be pending, approved or rejected.');
    }

    const existing = get('SELECT id FROM inspections WHERE id = ?', req.params.id);
    if (!existing) throw ApiError.notFound('Inspection not found');

    run(
      `UPDATE inspections
          SET review_status = ?, review_note = ?, reviewed_by = ?, reviewed_at = ?
        WHERE id = ?`,
      status,
      req.body?.note ?? null,
      req.user.id,
      nowIso(),
      req.params.id,
    );

    recordAudit({
      actor: req.user,
      action: `inspection.${status}`,
      entityType: 'inspection',
      entityId: req.params.id,
      detail: { note: req.body?.note ?? null },
    });

    res.json({ ok: true, reviewStatus: status });
  }),
);
