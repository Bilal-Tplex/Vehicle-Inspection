import { api } from '../api.js';
import { navigate } from '../router.js';
import {
  el, emptyState, fmt, gradeBadge, icon, notifyError, reviewBadge, skeletonRows, toast,
} from '../ui.js';

const state = { search: '', grade: '', review: '', offset: 0, limit: 25 };

export async function renderInspections(host) {
  const results = el('div.card__body.card__body--flush', skeletonRows(5));
  const count = el('div', { style: 'font-size:12.5px;color:var(--text-muted)' });

  const searchInput = el('input.input', {
    type: 'search', placeholder: 'Registration, VIN, reference or evaluator', value: state.search,
    style: 'min-width:260px',
  });

  // Debounced so typing does not fire a query per keystroke.
  let debounce;
  searchInput.addEventListener('input', () => {
    clearTimeout(debounce);
    debounce = setTimeout(() => {
      state.search = searchInput.value.trim();
      state.offset = 0;
      load();
    }, 280);
  });

  const gradeSelect = el('select.select', { style: 'width:auto' },
    el('option', { value: '' }, 'All grades'),
    ...['A', 'B', 'C', 'D', 'F'].map((g) => el('option', { value: g, selected: state.grade === g }, `Grade ${g}`)));
  gradeSelect.addEventListener('change', () => {
    state.grade = gradeSelect.value;
    state.offset = 0;
    load();
  });

  const reviewSelect = el('select.select', { style: 'width:auto' },
    el('option', { value: '' }, 'Any review status'),
    ...[['pending', 'Pending review'], ['approved', 'Approved'], ['rejected', 'Rejected']].map(
      ([value, label]) => el('option', { value, selected: state.review === value }, label)));
  reviewSelect.addEventListener('change', () => {
    state.review = reviewSelect.value;
    state.offset = 0;
    load();
  });

  const exportButton = el('button.btn.btn--sm',
    { type: 'button', onclick: async () => {
      try {
        await api.download('/admin/reports/export.csv', 'inspections.csv');
        toast('Export downloaded', 'success');
      } catch (error) { notifyError(error); }
    } },
    icon('download', 15), 'Export CSV');

  const pager = el('div.row', { style: 'padding:12px 16px;border-top:1px solid var(--border)' });

  async function load() {
    results.replaceChildren(skeletonRows(5));
    const params = new URLSearchParams({ limit: state.limit, offset: state.offset });
    if (state.search) params.set('search', state.search);
    if (state.grade) params.set('grade', state.grade);
    if (state.review) params.set('review', state.review);

    try {
      const data = await api.get(`/admin/inspections?${params}`);
      count.textContent = `${fmt.number(data.total)} inspection${data.total === 1 ? '' : 's'}`;
      results.replaceChildren(
        data.inspections.length
          ? table(data.inspections)
          : emptyState('Nothing matches those filters',
              'Try clearing the search box or widening the grade filter.'),
      );
      renderPager(data);
    } catch (error) {
      notifyError(error);
      results.replaceChildren(emptyState('Could not load inspections', error.message));
    }
  }

  function renderPager(data) {
    const from = data.total === 0 ? 0 : data.offset + 1;
    const to = Math.min(data.offset + data.limit, data.total);
    pager.replaceChildren(
      el('span', { style: 'font-size:12.5px;color:var(--text-muted)' },
        `Showing ${from}-${to} of ${fmt.number(data.total)}`),
      el('div.spacer'),
      el('button.btn.btn--sm', {
        type: 'button', disabled: data.offset === 0,
        onclick: () => { state.offset = Math.max(0, state.offset - state.limit); load(); },
      }, 'Previous'),
      el('button.btn.btn--sm', {
        type: 'button', disabled: to >= data.total,
        onclick: () => { state.offset += state.limit; load(); },
      }, 'Next'));
  }

  host.replaceChildren(el('div.stack',
    el('div.card',
      el('div.card__header',
        el('div', el('h2', 'Inspections'), count),
        el('div.spacer'),
        exportButton),
      el('div.card__body', el('div.row.row--wrap', searchInput, gradeSelect, reviewSelect)),
      results,
      pager)));

  load();
}

const COLUMNS = [
  'Grade', 'Vehicle', 'Reference', 'Evaluator',
  'Score', 'Points', 'Media', 'Review', 'Received',
];

const muted = { style: 'color:var(--text-muted)' };

function inspectionRow(row) {
  const vehicle = el('td',
    el('div', { style: 'font-weight:600' }, row.registrationNumber),
    el('div', { style: 'color:var(--text-muted);font-size:12.5px' },
      `${row.vehicleName} · ${row.manufacturingYear}`));

  return el('tr.is-clickable',
    { onclick: () => navigate(`/inspections/${row.id}`) },
    el('td', gradeBadge(row.gradeCode)),
    vehicle,
    el('td.mono', row.referenceNumber),
    el('td', row.evaluatorName),
    el('td.num', { style: 'font-weight:650' }, fmt.percent(row.scorePercentage)),
    el('td.num', muted, `${row.obtainedPoints}/${row.maxPoints}`),
    el('td.num', muted, row.photoCount || '--'),
    el('td', reviewBadge(row.reviewStatus)),
    el('td', muted, fmt.relative(row.receivedAt)));
}

function table(rows) {
  const head = el('thead', el('tr', ...COLUMNS.map((label) => el('th', label))));
  const body = el('tbody', ...rows.map(inspectionRow));
  return el('div.table-wrap', el('table', head, body));
}
