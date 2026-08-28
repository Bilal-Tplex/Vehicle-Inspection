import { api, session } from '../api.js';
import {
  el, emptyState, fmt, icon, modal, notifyError, skeletonRows, toast,
} from '../ui.js';

const ROLE_LABEL = {
  admin: 'Admin — full access',
  reviewer: 'Reviewer — read only',
  evaluator: 'Evaluator — mobile app',
};

const roleBadge = (role) =>
  el(`span.badge.badge--${role === 'admin' ? 'brand' : role === 'reviewer' ? 'minor' : 'na'}`,
    role[0].toUpperCase() + role.slice(1));

export async function renderUsers(host) {
  host.replaceChildren(skeletonRows(4));

  const reload = () => renderUsers(host);
  let users;
  try {
    ({ users } = await api.get('/admin/users'));
  } catch (error) {
    notifyError(error);
    host.replaceChildren(emptyState('Could not load accounts', error.message));
    return;
  }

  const addButton = session.isAdmin
    ? el('button.btn.btn--primary.btn--sm', { type: 'button', onclick: () => addUser(reload) },
        icon('plus', 15), 'Add account')
    : null;

  host.replaceChildren(el('div.stack',
    el('div.card',
      el('div.card__header',
        el('div',
          el('h2', 'Evaluators & roles'),
          el('div', { style: 'font-size:12.5px;color:var(--text-muted)' },
            'Evaluators sign in on the mobile app; admins and reviewers use this dashboard')),
        el('div.spacer'),
        addButton),
      el('div.card__body.card__body--flush',
        el('div.table-wrap',
          el('table',
            el('thead', el('tr',
              el('th', 'Name'), el('th', 'Email'), el('th', 'Role'), el('th', 'Branch'),
              el('th', 'Inspections'), el('th', 'Last submitted'), el('th', 'Status'), el('th', ''))),
            el('tbody', ...users.map((user) => row(user, reload)))))))));
}

const row = (user, reload) =>
  el('tr',
    el('td',
      el('div.row', { style: 'gap:9px' },
        el('div.avatar', fmt.initials(user.name)),
        el('div', { style: 'font-weight:600' }, user.name))),
    el('td', { style: 'color:var(--text-muted)' }, user.email),
    el('td', roleBadge(user.role)),
    el('td', { style: 'color:var(--text-muted)' }, user.branch ?? '--'),
    el('td.num', user.role === 'evaluator' ? fmt.number(user.inspectionCount) : '--'),
    el('td', { style: 'color:var(--text-muted)' },
      user.role === 'evaluator' ? fmt.relative(user.lastSubmittedAt) : '--'),
    el('td', user.isActive
      ? el('span.badge.badge--pass', 'Active')
      : el('span.badge.badge--fail', 'Disabled')),
    el('td', { style: 'text-align:right;white-space:nowrap' },
      session.isAdmin
        ? [
            el('button.btn.btn--sm', { type: 'button', onclick: () => editUser(user, reload) }, 'Edit'),
            ' ',
            el('button.btn.btn--sm.btn--ghost', {
              type: 'button', onclick: () => resetPassword(user),
            }, 'Reset password'),
          ]
        : null));

function userFields(user = {}) {
  const name = el('input.input', { value: user.name ?? '' });
  const email = el('input.input', {
    type: 'email', value: user.email ?? '', disabled: Boolean(user.id),
  });
  const branch = el('input.input', { value: user.branch ?? '' });
  const role = el('select.select',
    ...Object.entries(ROLE_LABEL).map(([value, label]) =>
      el('option', { value, selected: (user.role ?? 'evaluator') === value }, label)));
  return { name, email, branch, role };
}

async function addUser(reload) {
  const fields = userFields();
  const password = el('input.input', { type: 'text', value: '', placeholder: 'At least 6 characters' });

  const created = await modal({
    title: 'Add account',
    confirmLabel: 'Create',
    body: el('div.stack',
      el('div.field', el('label.field__label', 'Full name'), fields.name),
      el('div.field', el('label.field__label', 'Email'), fields.email),
      el('div.field',
        el('label.field__label', 'Temporary password'), password,
        el('div.field__hint', 'Shown in plain text here so you can pass it on; stored hashed.')),
      el('div.field', el('label.field__label', 'Role'), fields.role),
      el('div.field', el('label.field__label', 'Branch'), fields.branch)),
    onConfirm: () => api.post('/admin/users', {
      name: fields.name.value.trim(),
      email: fields.email.value.trim(),
      password: password.value,
      role: fields.role.value,
      branch: fields.branch.value.trim() || null,
    }),
  });

  if (created) {
    toast('Account created', 'success');
    reload();
  }
}

async function editUser(user, reload) {
  const fields = userFields(user);
  const active = el('input', { type: 'checkbox', checked: user.isActive });

  const saved = await modal({
    title: `Edit ${user.name}`,
    confirmLabel: 'Save',
    body: el('div.stack',
      el('div.field', el('label.field__label', 'Full name'), fields.name),
      el('div.field', el('label.field__label', 'Email'), fields.email),
      el('div.field', el('label.field__label', 'Role'), fields.role),
      el('div.field', el('label.field__label', 'Branch'), fields.branch),
      el('label.switch', active, 'Active — unchecking signs the account out everywhere')),
    onConfirm: () => api.patch(`/admin/users/${user.id}`, {
      name: fields.name.value.trim(),
      role: fields.role.value,
      branch: fields.branch.value.trim() || null,
      isActive: active.checked,
    }),
  });

  if (saved) {
    toast('Account updated', 'success');
    reload();
  }
}

async function resetPassword(user) {
  const password = el('input.input', { type: 'text', placeholder: 'At least 6 characters' });

  const done = await modal({
    title: `Reset password for ${user.name}`,
    confirmLabel: 'Reset',
    danger: true,
    body: el('div.stack',
      el('div', { style: 'color:var(--text-muted)' },
        'Every signed-in device for this account will be signed out immediately.'),
      el('div.field', el('label.field__label', 'New password'), password)),
    onConfirm: () => api.post(`/admin/users/${user.id}/password`, { password: password.value }),
  });

  if (done) toast('Password reset', 'success');
}
