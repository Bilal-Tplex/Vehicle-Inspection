import { api, session } from '../api.js';
import { navigate } from '../router.js';
import {
  el, emptyState, fmt, icon, modal, notifyError, skeletonRows, toast,
} from '../ui.js';

/** Slugifies a name into an id an inspection can reference forever. */
const slugify = (value) =>
  value.toLowerCase().trim().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 48);

export async function renderTemplates(host) {
  host.replaceChildren(skeletonRows(3));

  let templates;
  try {
    ({ templates } = await api.get('/admin/templates'));
  } catch (error) {
    notifyError(error);
    host.replaceChildren(emptyState('Could not load templates', error.message));
    return;
  }

  const newButton = session.isAdmin
    ? el('button.btn.btn--primary.btn--sm', { type: 'button', onclick: () => createTemplate(host) },
        icon('plus', 15), 'New template')
    : null;

  host.replaceChildren(el('div.stack',
    el('div.card',
      el('div.card__header',
        el('div',
          el('h2', 'Checklist templates'),
          el('div', { style: 'font-size:12.5px;color:var(--text-muted)' },
            'Published templates are pulled by the mobile app on its next sync')),
        el('div.spacer'),
        newButton),
      templates.length
        ? el('div.card__body.card__body--flush', list(templates, host))
        : emptyState('No templates yet', 'Create one to get started.', newButton))));
}

const list = (templates, host) =>
  el('div.table-wrap',
    el('table',
      el('thead', el('tr',
        el('th', 'Template'), el('th', 'Version'), el('th', 'Structure'),
        el('th', 'Grading'), el('th', 'Status'), el('th', 'Updated'), el('th', ''))),
      el('tbody', ...templates.map((template) => {
        const bands = template.gradingRules?.bands?.length ?? 0;
        const pass = template.gradingRules?.statusPoints?.pass ?? '--';
        return el('tr.is-clickable',
          { onclick: () => navigate(`/templates/${template.id}`) },
          el('td',
            el('div', { style: 'font-weight:600' }, template.name),
            el('div.mono', { style: 'color:var(--text-faint);font-size:11.5px' }, template.id)),
          el('td.num', `v${template.version}`),
          el('td', { style: 'color:var(--text-muted)' },
            `${template.categories.length} categories · ${template.pointCount} points`),
          el('td', { style: 'color:var(--text-muted)' }, `Pass=${pass} · ${bands} bands`),
          el('td',
            template.isDefault ? el('span.badge.badge--brand', 'Default') : null,
            ' ',
            template.isPublished
              ? el('span.badge.badge--pass', 'Published')
              : el('span.badge.badge--minor', 'Draft')),
          el('td', { style: 'color:var(--text-muted)' }, fmt.relative(template.updatedAt)),
          el('td', { style: 'text-align:right' },
            el('button.btn.btn--sm', {
              type: 'button',
              onclick: (event) => { event.stopPropagation(); navigate(`/templates/${template.id}`); },
            }, session.isAdmin ? 'Edit' : 'View')));
      }))));

async function createTemplate(host) {
  const nameInput = el('input.input', { placeholder: 'e.g. Commercial Vehicle Inspection' });
  const descriptionInput = el('input.input', { placeholder: 'Optional description' });

  const created = await modal({
    title: 'New template',
    confirmLabel: 'Create draft',
    body: el('div.stack',
      el('div.field',
        el('label.field__label', 'Name'), nameInput,
        el('div.field__hint', 'A starter category with one point is created for you.')),
      el('div.field', el('label.field__label', 'Description'), descriptionInput)),
    onConfirm: async () => {
      const name = nameInput.value.trim();
      if (!name) throw new Error('Give the template a name.');

      const id = slugify(name) || `template-${Date.now()}`;
      const categoryId = `${id}-cat-1`;

      return api.post('/admin/templates', {
        id,
        name,
        description: descriptionInput.value.trim() || null,
        categories: [{
          id: categoryId,
          code: 'CAT',
          title: 'New category',
          iconName: 'exterior',
          points: [{
            id: `${categoryId}-p1`,
            code: 'CAT-01',
            title: 'New inspection point',
            description: null,
            isRequired: true,
            allowsNotApplicable: true,
            requiresPhotoOnFail: false,
            maxPhotos: 3,
            weight: 1,
          }],
        }],
      });
    },
  });

  if (created) {
    toast('Draft created', 'success');
    navigate(`/templates/${created.template.id}`);
  }
}
