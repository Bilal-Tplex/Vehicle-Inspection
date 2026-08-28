import { Router } from 'express';

import { all, get } from '../db/database.js';
import { authenticate, requireDashboard } from '../middleware/auth.js';
import { asyncRoute } from '../middleware/errors.js';
import { listAudit } from '../services/audit.js';

export const reportRouter = Router();

reportRouter.use(authenticate, requireDashboard);

/**
 * Everything the overview screen needs, in one round trip.
 *
 * Aggregates are computed in SQL rather than by pulling rows into Node — the
 * dashboard should stay responsive when the table holds years of inspections.
 */
reportRouter.get(
  '/summary',
  asyncRoute((_req, res) => {
    const totals = get(
      `SELECT COUNT(*)                                        AS total,
              AVG(score_percentage)                           AS average_score,
              SUM(CASE WHEN review_status = 'pending'  THEN 1 ELSE 0 END) AS pending_review,
              SUM(CASE WHEN review_status = 'approved' THEN 1 ELSE 0 END) AS approved,
              SUM(CASE WHEN review_status = 'rejected' THEN 1 ELSE 0 END) AS rejected
         FROM inspections`,
    );

    const grades = all(
      `SELECT grade_code AS code, COUNT(*) AS count
         FROM inspections
        WHERE grade_code IS NOT NULL
        GROUP BY grade_code
        ORDER BY grade_code ASC`,
    );

    const byEvaluator = all(
      `SELECT evaluator_id   AS id,
              evaluator_name AS name,
              COUNT(*)       AS count,
              AVG(score_percentage) AS average_score,
              MAX(submitted_at)     AS last_submitted_at
         FROM inspections
        GROUP BY evaluator_id, evaluator_name
        ORDER BY count DESC`,
    );

    // Daily volume for the trend line. SQLite has no date type, but the
    // timestamps are ISO-8601 so a substring is a valid day key.
    const daily = all(
      `SELECT substr(received_at, 1, 10) AS day,
              COUNT(*)                   AS count,
              AVG(score_percentage)      AS average_score
         FROM inspections
        GROUP BY day
        ORDER BY day DESC
        LIMIT 30`,
    );

    const defects = all(
      `SELECT it.point_id                                          AS point_id,
              COUNT(*)                                             AS total,
              SUM(CASE WHEN it.status = 'fail' THEN 1 ELSE 0 END)   AS fail_count,
              SUM(CASE WHEN it.status = 'minor_issue' THEN 1 ELSE 0 END)
                                                                   AS minor_count,
              tp.title                                             AS title,
              tp.code                                              AS code
         FROM inspection_items it
         JOIN inspections i ON i.id = it.inspection_id
         LEFT JOIN template_points tp
           ON tp.id = it.point_id
          AND tp.template_id = i.template_id
          AND tp.template_version = i.template_version
        WHERE it.status IN ('fail', 'minor_issue')
        GROUP BY it.point_id, tp.title, tp.code
        ORDER BY fail_count DESC, minor_count DESC
        LIMIT 10`,
    );

    const media = get(
      'SELECT COUNT(*) AS count, COALESCE(SUM(byte_size), 0) AS bytes FROM inspection_photos',
    );

    res.json({
      totals: {
        inspections: totals?.total ?? 0,
        averageScore: totals?.average_score ?? null,
        pendingReview: totals?.pending_review ?? 0,
        approved: totals?.approved ?? 0,
        rejected: totals?.rejected ?? 0,
        photos: media?.count ?? 0,
        mediaBytes: media?.bytes ?? 0,
      },
      grades,
      byEvaluator: byEvaluator.map((row) => ({
        id: row.id,
        name: row.name,
        count: row.count,
        averageScore: row.average_score,
        lastSubmittedAt: row.last_submitted_at,
      })),
      daily: daily.reverse(),
      topDefects: defects.map((row) => ({
        pointId: row.point_id,
        code: row.code ?? row.point_id,
        title: row.title ?? 'Removed from template',
        failCount: row.fail_count,
        minorCount: row.minor_count,
        total: row.total,
      })),
    });
  }),
);

const csvCell = (value) => {
  const text = value == null ? '' : String(value);
  // Quote anything that could break a cell, and double any embedded quotes.
  return /[",\n\r]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
};

/** Inspection export for spreadsheets. */
reportRouter.get(
  '/export.csv',
  asyncRoute((_req, res) => {
    const rows = all(
      `SELECT reference_number, registration_number, make, model,
              manufacturing_year, vin, mileage_km, evaluator_name,
              score_percentage, grade_code, obtained_points, max_points,
              total_items, completed_items, review_status, submitted_at,
              received_at
         FROM inspections
        ORDER BY received_at DESC`,
    );

    const headers = [
      'Reference', 'Registration', 'Make', 'Model', 'Year', 'VIN', 'Mileage (km)',
      'Evaluator', 'Score %', 'Grade', 'Points', 'Max points', 'Total items',
      'Completed items', 'Review', 'Submitted at', 'Received at',
    ];

    const lines = [headers.join(',')];
    for (const row of rows) {
      lines.push(
        [
          row.reference_number, row.registration_number, row.make, row.model,
          row.manufacturing_year, row.vin, row.mileage_km, row.evaluator_name,
          row.score_percentage == null ? '' : row.score_percentage.toFixed(1),
          row.grade_code, row.obtained_points, row.max_points, row.total_items,
          row.completed_items, row.review_status, row.submitted_at, row.received_at,
        ]
          .map(csvCell)
          .join(','),
      );
    }

    const stamp = new Date().toISOString().slice(0, 10);
    res.type('text/csv').set(
      'Content-Disposition',
      `attachment; filename="inspections-${stamp}.csv"`,
    );
    // BOM so Excel opens UTF-8 correctly.
    res.send(`﻿${lines.join('\r\n')}\r\n`);
  }),
);

reportRouter.get(
  '/audit',
  asyncRoute((req, res) => {
    res.json({ entries: listAudit({ limit: Number(req.query.limit ?? 100) }) });
  }),
);
