import { api } from '../api.js';
import {
  el, emptyState, fmt, icon, notifyError, skeletonRows, toast,
} from '../ui.js';

const ACTION_LABEL = {
  'inspection.submit': 'Inspection submitted',
  'inspection.approved': 'Inspection approved',
  'inspection.rejected': 'Inspection rejected',
  'inspection.pending': 'Inspection reopened',
  'inspection.grade_mismatch': 'Grade mismatch detected',
  'template.create': 'Template created',
  'template.update_draft': 'Template draft updated',
  'template.new_version': 'New template version',
  'template.publish': 'Template published',
  'template.delete_draft': 'Template draft deleted',
  'user.create': 'Account created',
  'user.update': 'Account updated',
  'user.reset_password': 'Password reset',
};

export async function renderReports(host) {
  host.replaceChildren(skeletonRows(4));

  let summary;
  let audit;
  try {
    [summary, audit] = await Promise.all([
      api.get('/admin/reports/summary'),
      api.get('/admin/reports/audit?limit=60'),
    ]);
  } catch (error) {
    notifyError(error);
    host.replaceChildren(emptyState('Could not load reports', error.message));
    return;
  }

  const { totals, grades, byEvaluator, topDefects } = summary;
  const gradeTotal = grades.reduce((n, g) => n + g.count, 0) || 1;

  host.replaceChildren(el('div.stack',
    el('div.card',
      el('div.card__header',
        el('div',
          el('h2', 'Reports'),
          el('div', { style: 'font-size:12.5px;color:var(--text-muted)' },
            'Aggregates are computed from stored answers, so a corrected grading rule can be replayed over history')),
        el('div.spacer'),
        el('button.btn.btn--sm.btn--primary', {
          type: 'button',
          onclick: async () => {
            try {
              await api.download('/admin/reports/export.csv', 'inspections.csv');
              toast('Export downloaded', 'success');
            } catch (error) { notifyError(error); }
          },
        }, icon('download', 15), 'Export inspections (CSV)')),
      el('div.card__body',
        el('div.grid.grid--stats',
          stat('Total inspections', fmt.number(totals.inspections)),
          stat('Average score', fmt.percent(totals.averageScore)),
          stat('Approved', fmt.number(totals.approved)),
          stat('Rejected', fmt.number(totals.rejected)),
          stat('Awaiting review', fmt.number(totals.pendingReview)),
          stat('Media stored', fmt.bytes(totals.mediaBytes),
            `${fmt.number(totals.photos)} photos`)))),

    el('div.grid.grid--2',
      el('div.card',
        el('div.card__header', el('h2', 'Grade distribution')),
        el('div.card__body.card__body--flush',
          el('div.table-wrap',
            el('table',
              el('thead', el('tr', el('th', 'Grade'), el('th', 'Count'), el('th', 'Share'))),
              el('tbody', ...grades.map((g) =>
                el('tr',
                  el('td', el('strong', g.code)),
                  el('td.num', fmt.number(g.count)),
                  el('td.num', `${((g.count / gradeTotal) * 100).toFixed(1)}%`)))))))),

      el('div.card',
        el('div.card__header', el('h2', 'Evaluator performance')),
        el('div.card__body.card__body--flush',
          el('div.table-wrap',
            el('table',
              el('thead', el('tr',
                el('th', 'Evaluator'), el('th', 'Inspections'), el('th', 'Avg score'))),
              el('tbody', ...byEvaluator.map((row) =>
                el('tr',
                  el('td', row.name),
                  el('td.num', fmt.number(row.count)),
                  el('td.num', fmt.percent(row.averageScore)))))))))),

    el('div.card',
      el('div.card__header', el('h2', 'Most frequent defects')),
      topDefects.length
        ? el('div.card__body.card__body--flush',
            el('div.table-wrap',
              el('table',
                el('thead', el('tr',
                  el('th', 'Code'), el('th', 'Point'), el('th', 'Failed'),
                  el('th', 'Minor'), el('th', 'Total'))),
                el('tbody', ...topDefects.map((d) =>
                  el('tr',
                    el('td.mono', d.code),
                    el('td', d.title),
                    el('td.num', { style: 'color:var(--fail);font-weight:650' }, d.failCount),
                    el('td.num', { style: 'color:var(--minor)' }, d.minorCount),
                    el('td.num', d.total)))))))
        : emptyState('No defects recorded yet', null)),

    el('div.card',
      el('div.card__header',
        el('div',
          el('h2', 'Activity log'),
          el('div', { style: 'font-size:12.5px;color:var(--text-muted)' },
            'Template and grading changes decide what an inspection is worth, so each one is attributed'))),
      audit.entries.length
        ? auditTable(audit.entries)
        : emptyState('No activity yet', null))));
}

function auditRow(entry) {
  return el('tr',
    el('td', { style: 'color:var(--text-muted);white-space:nowrap' },
      fmt.dateTime(entry.createdAt)),
    el('td', entry.actorName),
    el('td', ACTION_LABEL[entry.action] ?? entry.action),
    el('td.mono', { style: 'color:var(--text-muted);font-size:11.5px' },
      entry.detail ? summarise(entry.detail) : '--'));
}

function auditTable(entries) {
  const head = el('thead', el('tr',
    ...['When', 'Who', 'Action', 'Detail'].map((label) => el('th', label))));
  const body = el('tbody', ...entries.map(auditRow));
  return el('div.card__body.card__body--flush',
    el('div.table-wrap', el('table', head, body)));
}

const stat = (label, value, hint) =>
  el('div.card', el('div.stat',
    el('div.stat__label', label),
    el('div.stat__value', value),
    hint && el('div.stat__hint', hint)));

/** Flattens an audit detail object into one readable line. */
const summarise = (detail) =>
  Object.entries(detail)
    .filter(([, value]) => value != null && typeof value !== 'object')
    .map(([key, value]) => `${key}=${value}`)
    .join('  ') || JSON.stringify(detail);
