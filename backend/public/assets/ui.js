/** Small DOM and formatting helpers. No framework, no build step. */

/**
 * Creates an element.
 *
 * `el('div.card', {onclick}, child, 'text')` — tag string carries classes, the
 * optional second argument is props, everything after is children.
 */
export function el(spec, props = null, ...children) {
  const [tag, ...classes] = String(spec).split('.');
  const node = document.createElement(tag || 'div');
  if (classes.length) node.className = classes.join(' ');

  if (props && (props.nodeType || Array.isArray(props) || typeof props === 'string')) {
    children.unshift(props);
  } else if (props) {
    for (const [key, value] of Object.entries(props)) {
      if (value == null || value === false) continue;
      if (key === 'class') node.className = [node.className, value].filter(Boolean).join(' ');
      else if (key === 'html') node.innerHTML = value;
      else if (key === 'dataset') Object.assign(node.dataset, value);
      else if (key.startsWith('on') && typeof value === 'function') {
        node.addEventListener(key.slice(2).toLowerCase(), value);
      } else if (key in node && key !== 'list') node[key] = value;
      else node.setAttribute(key, value);
    }
  }

  for (const child of children.flat(4)) {
    if (child == null || child === false) continue;
    node.append(child.nodeType ? child : document.createTextNode(String(child)));
  }
  return node;
}

export const clear = (node) => {
  node.replaceChildren();
  return node;
};

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

const dateFmt = new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
const timeFmt = new Intl.DateTimeFormat(undefined, {
  day: 'numeric', month: 'short', year: 'numeric', hour: 'numeric', minute: '2-digit',
});

export const fmt = {
  date: (iso) => (iso ? dateFmt.format(new Date(iso)) : '--'),
  dateTime: (iso) => (iso ? timeFmt.format(new Date(iso)) : '--'),

  relative(iso) {
    if (!iso) return '--';
    const days = Math.floor((Date.now() - new Date(iso)) / 86_400_000);
    if (days <= 0) return 'Today';
    if (days === 1) return 'Yesterday';
    if (days < 7) return `${days} days ago`;
    return dateFmt.format(new Date(iso));
  },

  percent: (value) => (value == null ? '--' : `${Number(value).toFixed(1)}%`),
  number: (value) => new Intl.NumberFormat().format(value ?? 0),

  bytes(value) {
    if (!value) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    const power = Math.min(Math.floor(Math.log(value) / Math.log(1024)), units.length - 1);
    return `${(value / 1024 ** power).toFixed(power === 0 ? 0 : 1)} ${units[power]}`;
  },

  initials(name) {
    const parts = String(name ?? '').trim().split(/\s+/).filter(Boolean);
    if (!parts.length) return '?';
    if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
    return (parts[0][0] + parts.at(-1)[0]).toUpperCase();
  },
};

/** Checklist status -> label + badge modifier. */
export const STATUS = {
  pass: { label: 'Pass', mod: 'pass' },
  minor_issue: { label: 'Minor Issue', mod: 'minor' },
  fail: { label: 'Fail', mod: 'fail' },
  na: { label: 'N/A', mod: 'na' },
  pending: { label: 'Not checked', mod: 'pending' },
};

export const statusBadge = (status) => {
  const meta = STATUS[status] ?? STATUS.pending;
  return el(`span.badge.badge--${meta.mod}`, meta.label);
};

export const gradeBadge = (code) =>
  el(`div.grade.grade--${code && code !== '-' ? code : 'none'}`, code ?? '-');

export const reviewBadge = (status) => {
  const map = {
    approved: ['pass', 'Approved'],
    rejected: ['fail', 'Rejected'],
    pending: ['pending', 'Pending review'],
  };
  const [mod, label] = map[status] ?? map.pending;
  return el(`span.badge.badge--${mod}`, label);
};

// ---------------------------------------------------------------------------
// Icons (inline so there is no icon-font request)
// ---------------------------------------------------------------------------

const ICONS = {
  overview: 'M3 12h6v9H3zM10 3h4v18h-4zM15 8h6v13h-6z',
  inspections: 'M9 5H7a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-2M9 5a2 2 0 0 0 2 2h2a2 2 0 0 0 2-2M9 5a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2m-6 9 2 2 4-4',
  templates: 'M9 6h11M9 12h11M9 18h11M4 6h.01M4 12h.01M4 18h.01',
  users: 'M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8ZM23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75',
  reports: 'M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8zM14 2v6h6M16 13H8M16 17H8M10 9H8',
  car: 'M5 17h14M5 17a2 2 0 1 1-4 0 2 2 0 0 1 4 0Zm14 0a2 2 0 1 0 4 0 2 2 0 0 0-4 0ZM3 17v-5l2-5h14l2 5v5',
  search: 'M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16ZM21 21l-4.35-4.35',
  plus: 'M12 5v14M5 12h14',
  trash: 'M3 6h18M8 6V4a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v2m3 0v14a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V6',
  back: 'M19 12H5M12 19l-7-7 7-7',
  drag: 'M9 5h.01M9 12h.01M9 19h.01M15 5h.01M15 12h.01M15 19h.01',
  logout: 'M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9',
  sun: 'M12 17a5 5 0 1 0 0-10 5 5 0 0 0 0 10ZM12 1v2M12 21v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M1 12h2M21 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4',
  moon: 'M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z',
  menu: 'M3 12h18M3 6h18M3 18h18',
  download: 'M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3',
  check: 'M20 6 9 17l-5-5',
  close: 'M18 6 6 18M6 6l12 12',
  empty: 'M20 13V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v7m16 0-2 7H6l-2-7m16 0h-4l-1 3h-6l-1-3H4',
};

export function icon(name, size = 17) {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('width', size);
  svg.setAttribute('height', size);
  svg.setAttribute('fill', 'none');
  svg.setAttribute('stroke', 'currentColor');
  svg.setAttribute('stroke-width', '1.9');
  svg.setAttribute('stroke-linecap', 'round');
  svg.setAttribute('stroke-linejoin', 'round');

  const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
  path.setAttribute('d', ICONS[name] ?? ICONS.empty);
  svg.append(path);
  return svg;
}

// ---------------------------------------------------------------------------
// Feedback
// ---------------------------------------------------------------------------

const toastHost = el('div.toasts');
document.addEventListener('DOMContentLoaded', () => document.body.append(toastHost));

export function toast(message, kind = 'info') {
  const node = el(`div.toast.toast--${kind}`, icon(kind === 'error' ? 'close' : 'check', 15), el('span', message));
  toastHost.append(node);
  setTimeout(() => node.remove(), 4200);
}

export const notifyError = (error) => {
  console.error(error);
  toast(error?.message ?? 'Something went wrong', 'error');
};

export const emptyState = (title, message, action) =>
  el('div.empty',
    el('div.empty__icon', icon('empty', 34)),
    el('div.empty__title', title),
    message && el('div', message),
    action && el('div', { style: 'margin-top:16px' }, action));

export const skeletonRows = (rows = 4) =>
  el('div', { style: 'padding:18px;display:flex;flex-direction:column;gap:10px' },
    ...Array.from({ length: rows }, () => el('div.skeleton', { style: 'height:34px' })));

/**
 * Modal dialog. Resolves with the value passed to `close`, or `null` when
 * dismissed via backdrop or Escape.
 */
export function modal({ title, body, confirmLabel = 'Save', danger = false, onConfirm }) {
  return new Promise((resolve) => {
    const finish = (value) => {
      document.removeEventListener('keydown', onKey);
      backdrop.remove();
      resolve(value);
    };
    const onKey = (event) => event.key === 'Escape' && finish(null);

    const confirmButton = el(
      `button.btn.${danger ? 'btn--danger' : 'btn--primary'}`,
      { type: 'button', onclick: async () => {
        confirmButton.disabled = true;
        try {
          finish(onConfirm ? await onConfirm() : true);
        } catch (error) {
          notifyError(error);
          confirmButton.disabled = false;
        }
      } },
      confirmLabel,
    );

    const backdrop = el('div.modal-backdrop',
      { onclick: (event) => event.target === backdrop && finish(null) },
      el('div.modal',
        el('div.modal__header', el('h2', title)),
        el('div.modal__body', body),
        el('div.modal__footer',
          el('button.btn', { type: 'button', onclick: () => finish(null) }, 'Cancel'),
          confirmButton)));

    document.addEventListener('keydown', onKey);
    document.body.append(backdrop);
    backdrop.querySelector('input,select,textarea')?.focus();
  });
}

export const confirmDialog = (title, message, confirmLabel = 'Confirm') =>
  modal({ title, body: el('div', message), confirmLabel, danger: true, onConfirm: () => true });

/** Full-screen image viewer with keyboard paging. */
export function lightbox(urls, startIndex = 0) {
  let index = startIndex;
  const image = el('img', { src: urls[index], alt: '' });

  const move = (delta) => {
    index = (index + delta + urls.length) % urls.length;
    image.src = urls[index];
    counter.textContent = `${index + 1} / ${urls.length}`;
  };
  const counter = el('span.badge.badge--brand', `${index + 1} / ${urls.length}`);

  const onKey = (event) => {
    if (event.key === 'Escape') close();
    if (event.key === 'ArrowRight') move(1);
    if (event.key === 'ArrowLeft') move(-1);
  };
  const close = () => {
    document.removeEventListener('keydown', onKey);
    box.remove();
  };

  const box = el('div.lightbox', { onclick: (event) => event.target === box && close() },
    el('div.lightbox__bar',
      urls.length > 1 && counter,
      el('button.btn.btn--sm', { type: 'button', onclick: close }, icon('close', 15), 'Close')),
    image);

  document.addEventListener('keydown', onKey);
  document.body.append(box);
}
