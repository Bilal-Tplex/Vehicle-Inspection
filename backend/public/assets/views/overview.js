import { api } from '../api.js';
import { navigate } from '../router.js';
import {
  el, emptyState, fmt, gradeBadge, icon, notifyError, skeletonRows,
} from '../ui.js';

const statCard = (label, value, hint) =>
  el('div.card', el('div.stat',
    el('div.stat__label', label),
    el('div.stat__value', value),
    hint && el('div.stat__hint', hint)));

/** Horizontal bars, scaled to the largest value. No charting library. */
function barChart(rows, { colorFor } = {}) {
  const max = Math.max(1, ...rows.map((row) => row.value));
  return el('div.bars', ...rows.map((row) =>
    el('div.bar__row',
      el('div.bar__label', { title: row.label }, row.label),
      el('div.bar__track',
        el('div.bar__fill', {
          style: `width:${(row.value / max) * 100}%${colorFor ? `;background:${colorFor(row)}` : ''}`,
        })),
      el('div.bar__value', row.display ?? fmt.number(row.value)))));
}

/** Daily volume as a sparkline of stacked divs. */
function sparkline(daily) {
  const max = Math.max(1, ...daily.map((d) => d.count));
  return el('div.spark', ...daily.map((day) =>
    el('div.spark__bar', { title: `${day.day}: ${day.count} inspection(s)` },
      el('span', { style: `height:${(day.count / max) * 100}%` }))));
}

export async function renderOverview(host) {
  host.replaceChildren(skeletonRows(3));

  let summary;
  try {
    summary = await api.get('/admin/reports/summary');
  } catch (error) {
    notifyError(error);
    host.replaceChildren(emptyState('Could not load the overview', error.message));
    return;
  }

  const { totals, grades, byEvaluator, daily, topDefects } = summary;

  if (totals.inspections === 0) {
    host.replaceChildren(
      emptyState(
        'No inspections yet',
        'Submit one from the mobile app and it will appear here within seconds.',
      ),
    );
    return;
  }

  const gradeColour = (row) =>
    ({ A: 'var(--pass)', B: 'var(--pass)', C: 'var(--minor)', D: 'var(--minor)', F: 'var(--fail)' })[
      row.label
    ] ?? 'var(--na)';

  host.replaceChildren(el('div.stack',
    el('div.grid.grid--stats',
      statCard('Inspections', fmt.number(totals.inspections), 'Received from the field'),
      statCard('Average score', fmt.percent(totals.averageScore),
        `${totals.approved} approved · ${totals.rejected} rejected`),
      statCard('Awaiting review', fmt.number(totals.pendingReview),
        totals.pendingReview ? 'Needs a reviewer' : 'All caught up'),
      statCard('Media stored', fmt.number(totals.photos), fmt.bytes(totals.mediaBytes))),

    el('div.grid.grid--2',
      el('div.card',
        el('div.card__header', el('h2', 'Grade distribution')),
        el('div.card__body',
          barChart(grades.map((g) => ({ label: g.code, value: g.count })), { colorFor: gradeColour }))),

      el('div.card',
        el('div.card__header', el('h2', 'Volume, last 30 days')),
        el('div.card__body',
          sparkline(daily),
          el('div', { style: 'display:flex;justify-content:space-between;margin-top:8px;font-size:11.5px;color:var(--text-faint)' },
            el('span', daily[0]?.day ?? ''),
            el('span', daily.at(-1)?.day ?? ''))))),

    el('div.grid.grid--2',
      el('div.card',
        el('div.card__header', el('h2', 'Most frequent defects')),
        topDefects.length
          ? el('div.card__body',
              barChart(topDefects.map((d) => ({
                label: `${d.code} ${d.title}`,
                value: d.failCount + d.minorCount,
                display: `${d.failCount}F / ${d.minorCount}m`,
              }))))
          : emptyState('No defects recorded', 'Every point has passed so far.')),

      el('div.card',
        el('div.card__header', el('h2', 'By evaluator')),
        el('div.card__body.card__body--flush',
          el('div.table-wrap',
            el('table',
              el('thead', el('tr',
                el('th', 'Evaluator'), el('th', 'Inspections'), el('th', 'Avg score'), el('th', 'Last'))),
              el('tbody', ...byEvaluator.map((row) =>
                el('tr',
                  el('td', row.name),
                  el('td.num', fmt.number(row.count)),
                  el('td.num', fmt.percent(row.averageScore)),
                  el('td', { style: 'color:var(--text-muted)' }, fmt.relative(row.lastSubmittedAt)))))))))),

    el('div.card',
      el('div.card__header',
        el('h2', 'Latest submissions'),
        el('div.spacer'),
        el('button.btn.btn--sm', { type: 'button', onclick: () => navigate('/inspections') },
          'View all')),
      el('div.card__body.card__body--flush', await latestTable()))));
}

async function latestTable() {
  const { inspections } = await api.get('/admin/inspections?limit=8');
  if (!inspections.length) return emptyState('Nothing yet', null);

  return el('div.table-wrap',
    el('table',
      el('thead', el('tr',
        el('th', 'Grade'), el('th', 'Vehicle'), el('th', 'Evaluator'),
        el('th', 'Score'), el('th', 'Received'))),
      el('tbody', ...inspections.map((row) =>
        el('tr.is-clickable', { onclick: () => navigate(`/inspections/${row.id}`) },
          el('td', gradeBadge(row.gradeCode)),
          el('td',
            el('div', { style: 'font-weight:600' }, row.registrationNumber),
            el('div', { style: 'color:var(--text-muted);font-size:12.5px' }, row.vehicleName)),
          el('td', row.evaluatorName),
          el('td.num', fmt.percent(row.scorePercentage)),
          el('td', { style: 'color:var(--text-muted)' }, fmt.relative(row.receivedAt)))))));
}
