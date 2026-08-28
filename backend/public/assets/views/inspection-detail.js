import { api, session } from '../api.js';
import { navigate } from '../router.js';
import {
  el, emptyState, fmt, gradeBadge, icon, lightbox, modal, notifyError,
  reviewBadge, skeletonRows, statusBadge, toast,
} from '../ui.js';

/** Label/value pair used by the vehicle and grading panels. */
const detailRow = (label, value) =>
  el('div', { style: 'display:flex;gap:12px;padding:6px 0' },
    el('div', { style: 'width:132px;flex:0 0 132px;color:var(--text-muted);font-size:12.5px' }, label),
    el('div', { style: 'font-weight:500' }, value ?? '--'));

/**
 * Loads a photo through the authenticated media endpoint.
 *
 * Inspection media is not public, so it cannot be a plain `<img src>` — the
 * bytes are fetched with the bearer token and handed to the tag as an object
 * URL instead.
 */
function thumbnail(photo, onOpen) {
  const image = el('img.thumb', { alt: 'Inspection photo', loading: 'lazy', onclick: onOpen });
  api
    .media(photo.url)
    .then((objectUrl) => { image.src = objectUrl; })
    .catch(() => { image.alt = 'Could not load photo'; });
  return image;
}

export async function renderInspectionDetail(host, { id }) {
  host.replaceChildren(skeletonRows(6));

  let data;
  try {
    data = await api.get(`/admin/inspections/${id}`);
  } catch (error) {
    notifyError(error);
    host.replaceChildren(emptyState('Could not load this inspection', error.message,
      el('button.btn', { type: 'button', onclick: () => navigate('/inspections') }, 'Back to list')));
    return;
  }

  const { inspection, items, photos, template, gradingRules } = data;

  // Resolve every photo URL once so the lightbox can page through them.
  const galleryUrls = [];
  const registerUrl = (url) => {
    const index = galleryUrls.length;
    galleryUrls.push(url);
    return index;
  };

  const counts = items.reduce((acc, item) => {
    acc[item.status] = (acc[item.status] ?? 0) + 1;
    return acc;
  }, {});

  const byCategory = new Map();
  for (const item of items) {
    const list = byCategory.get(item.categoryTitle) ?? [];
    list.push(item);
    byCategory.set(item.categoryTitle, list);
  }

  const band = (gradingRules?.bands ?? []).find((b) => b.code === inspection.gradeCode);

  host.replaceChildren(el('div.stack',
    el('div.row',
      el('button.btn.btn--sm', { type: 'button', onclick: () => navigate('/inspections') },
        icon('back', 15), 'All inspections'),
      el('div.spacer'),
      reviewBadge(inspection.reviewStatus),
      ...reviewActions(inspection, () => renderInspectionDetail(host, { id }))),

    // Header ---------------------------------------------------------------
    el('div.card', el('div.card__body',
      el('div.row.row--wrap', { style: 'gap:18px' },
        el('div', { style: 'display:flex;gap:14px;align-items:center' },
          el('div', { style: 'transform:scale(1.5);transform-origin:left center' },
            gradeBadge(inspection.gradeCode)),
          el('div', { style: 'margin-left:22px' },
            el('div', { style: 'font-size:25px;font-weight:700;line-height:1.1' },
              fmt.percent(inspection.scorePercentage)),
            el('div', { style: 'color:var(--text-muted);font-size:12.5px' },
              band ? `${band.label} · grade ${inspection.gradeCode}` : 'Ungraded',
              ` · ${inspection.obtainedPoints}/${inspection.maxPoints} points`))),
        el('div.spacer'),
        el('div', { style: 'text-align:right' },
          el('div', { style: 'font-size:19px;font-weight:700' }, inspection.registrationNumber),
          el('div', { style: 'color:var(--text-muted)' },
            `${inspection.vehicleName} · ${inspection.manufacturingYear}`))))),

    el('div.grid.grid--2',
      el('div.card',
        el('div.card__header', el('h2', 'Vehicle & capture')),
        el('div.card__body',
          detailRow('Registration', inspection.registrationNumber),
          detailRow('Make & model', inspection.vehicleName),
          detailRow('Year', inspection.manufacturingYear),
          detailRow('VIN', el('span.mono', inspection.vin)),
          detailRow('Mileage', `${fmt.number(inspection.mileageKm)} km`),
          detailRow('Inspection ID', el('span.mono', inspection.referenceNumber)),
          detailRow('Device id', el('span.mono', inspection.localId)),
          detailRow('Evaluator', inspection.evaluatorName),
          detailRow('Submitted', fmt.dateTime(inspection.submittedAt)),
          detailRow('Received', fmt.dateTime(inspection.receivedAt)),
          detailRow('Template',
            template ? `${template.name} v${template.version}` : 'Unknown'))),

      el('div.card',
        el('div.card__header', el('h2', 'Breakdown')),
        el('div.card__body',
          detailRow('Total points', items.length),
          detailRow('Completed', items.length - (counts.pending ?? 0)),
          el('hr', { style: 'border:none;border-top:1px solid var(--border);margin:10px 0' }),
          ...['pass', 'minor_issue', 'fail', 'na', 'pending']
            .filter((status) => counts[status])
            .map((status) =>
              el('div', { style: 'display:flex;align-items:center;gap:10px;padding:5px 0' },
                statusBadge(status),
                el('div.spacer'),
                el('div', { style: 'font-weight:700' }, counts[status]))),
          el('hr', { style: 'border:none;border-top:1px solid var(--border);margin:10px 0' }),
          detailRow('Score',
            `${inspection.obtainedPoints} of ${inspection.maxPoints} possible`),
          inspection.reviewNote && detailRow('Review note', inspection.reviewNote)))),

    // Media ----------------------------------------------------------------
    el('div.card',
      el('div.card__header', el('h2', `Media (${photos.length})`)),
      photos.length
        ? el('div.card__body',
            el('div.grid.grid--media', ...photos.map((photo) => {
              const index = registerUrl(photo.url);
              return thumbnail(photo, async () => {
                const resolved = await Promise.all(galleryUrls.map((url) => api.media(url)));
                lightbox(resolved, index);
              });
            })))
        : emptyState('No photos attached', 'This inspection was submitted without media.')),

    // Checklist ------------------------------------------------------------
    el('div.card',
      el('div.card__header', el('h2', 'Checklist')),
      el('div.card__body.card__body--flush',
        ...[...byCategory.entries()].map(([title, categoryItems]) =>
          categorySection(title, categoryItems, openGallery, registerUrl)))),
  ));

  /** Opens the lightbox at `index`, resolving every photo URL first. */
  async function openGallery(index) {
    const resolved = await Promise.all(galleryUrls.map((url) => api.media(url)));
    lightbox(resolved, index);
  }
}

/** One collapsible-looking block of the checklist. */
function categorySection(title, items, openGallery, registerUrl) {
  const answered = items.filter((item) => item.status !== 'pending').length;

  const header = el('div', {
    style: 'padding:10px 16px;background:var(--surface-2);border-bottom:1px solid var(--border);' +
           'font-weight:650;display:flex;gap:10px;align-items:center',
  },
    el('span', title),
    el('div.spacer'),
    el('span', { style: 'font-size:12px;color:var(--text-muted);font-weight:500' },
      `${answered}/${items.length}`));

  const body = el('tbody',
    ...items.map((item) => itemRow(item, openGallery, registerUrl)));

  return el('div', header, el('div.table-wrap', el('table', body)));
}

function itemRow(item, openGallery, registerUrl) {
  const detail = el('td', el('div', { style: 'font-weight:550' }, item.title));

  if (item.comment) {
    detail.append(el('div',
      { style: 'color:var(--text-muted);font-size:12.5px;margin-top:2px' },
      item.comment));
  }

  if (item.photos.length) {
    const strip = el('div', { style: 'display:flex;gap:6px;margin-top:7px' });
    for (const photo of item.photos) {
      const index = registerUrl(photo.url);
      const thumb = thumbnail(photo, () => openGallery(index));
      thumb.style.width = '54px';
      thumb.style.height = '54px';
      strip.append(thumb);
    }
    detail.append(strip);
  }

  return el('tr',
    el('td', { style: 'width:78px' }, el('span.mono', item.code)),
    detail,
    el('td', { style: 'width:120px;text-align:right' }, statusBadge(item.status)));
}

/** Approve / reject controls. Reviewers and admins both sign off. */
function reviewActions(inspection, refresh) {
  if (!['admin', 'reviewer'].includes(session.user?.role)) return [];

  const decide = async (reviewStatus, title, confirmLabel, danger) => {
    const note = el('textarea.textarea', {
      placeholder: reviewStatus === 'rejected'
        ? 'Why is this being sent back? The evaluator will see this.'
        : 'Optional note',
    });
    const confirmed = await modal({
      title, confirmLabel, danger,
      body: el('div.stack',
        el('div', `${inspection.registrationNumber} — ${fmt.percent(inspection.scorePercentage)}, grade ${inspection.gradeCode}`),
        el('div.field', el('label.field__label', 'Note'), note)),
      onConfirm: async () => {
        await api.patch(`/admin/inspections/${inspection.id}/review`, {
          reviewStatus, note: note.value.trim() || null,
        });
        return true;
      },
    });
    if (confirmed) {
      toast(`Inspection ${reviewStatus}`, reviewStatus === 'approved' ? 'success' : 'info');
      refresh();
    }
  };

  return [
    el('button.btn.btn--sm', {
      type: 'button',
      onclick: () => decide('rejected', 'Reject inspection', 'Reject', true),
    }, 'Reject'),
    el('button.btn.btn--sm.btn--primary', {
      type: 'button',
      onclick: () => decide('approved', 'Approve inspection', 'Approve', false),
    }, icon('check', 15), 'Approve'),
  ];
}
