import { api, session } from '../api.js';
import { navigate } from '../router.js';
import {
  confirmDialog, el, emptyState, fmt, icon, modal, notifyError, skeletonRows, toast,
} from '../ui.js';

/**
 * Template editor.
 *
 * The whole definition is held as a plain object and re-rendered on change, so
 * reordering is an array splice rather than DOM surgery. Point order is taken
 * from array position on save, which is what makes drag-and-drop reordering
 * work without a dedicated "sortOrder" input anywhere in the UI.
 *
 * Published versions are immutable — the server opens a new draft version when
 * one is edited — so nothing here can retroactively change a completed
 * inspection's questions.
 */
export async function renderTemplateEditor(host, { id }) {
  host.replaceChildren(skeletonRows(5));

  let payload;
  try {
    payload = await api.get(`/admin/templates/${id}`);
  } catch (error) {
    notifyError(error);
    host.replaceChildren(emptyState('Could not load this template', error.message,
      el('button.btn', { type: 'button', onclick: () => navigate('/templates') }, 'Back')));
    return;
  }

  // Deep clone so edits stay local until saved.
  let draft = structuredClone(payload.template);
  const versions = payload.versions;
  const readOnly = !session.isAdmin;
  let dirty = false;

  const body = el('div');
  const status = el('span', { style: 'font-size:12.5px;color:var(--text-muted)' });

  const markDirty = () => {
    dirty = true;
    status.textContent = 'Unsaved changes';
    saveButton.disabled = false;
  };

  const saveButton = el('button.btn.btn--primary.btn--sm', {
    type: 'button', disabled: true,
    onclick: async () => {
      saveButton.disabled = true;
      status.textContent = 'Saving...';
      try {
        const result = await api.put(`/admin/templates/${draft.id}`, {
          name: draft.name,
          description: draft.description,
          gradingRules: draft.gradingRules,
          categories: draft.categories,
        });
        draft = structuredClone(result.template);
        dirty = false;
        toast(
          result.createdNewVersion
            ? `Saved as draft v${result.template.version} — the published version is untouched`
            : 'Draft saved',
          'success',
        );
        renderTemplateEditor(host, { id });
      } catch (error) {
        notifyError(error);
        saveButton.disabled = false;
        status.textContent = 'Unsaved changes';
      }
    },
  }, 'Save draft');

  const publishButton = el('button.btn.btn--sm', {
    type: 'button',
    disabled: draft.isPublished,
    onclick: async () => {
      if (dirty) {
        toast('Save your changes before publishing', 'error');
        return;
      }
      const confirmed = await confirmDialog(
        'Publish this version?',
        `Version ${draft.version} becomes the template every phone pulls on its next sync. ` +
        'Inspections already captured keep grading against the version they used.',
        'Publish',
      );
      if (!confirmed) return;
      try {
        await api.post(`/admin/templates/${draft.id}/publish`, {
          version: draft.version, makeDefault: true,
        });
        toast('Published — devices will pick it up on next sync', 'success');
        renderTemplateEditor(host, { id });
      } catch (error) { notifyError(error); }
    },
  }, draft.isPublished ? 'Published' : 'Publish');

  const pointCount = () => draft.categories.reduce((n, c) => n + c.points.length, 0);

  // -------------------------------------------------------------------------
  // Rendering
  // -------------------------------------------------------------------------

  function repaint() {
    body.replaceChildren(el('div.stack',
      metaCard(),
      gradingCard(),
      structureCard()));
  }

  const metaCard = () => {
    const nameInput = el('input.input', { value: draft.name, disabled: readOnly });
    nameInput.addEventListener('input', () => { draft.name = nameInput.value; markDirty(); });

    const descriptionInput = el('input.input', {
      value: draft.description ?? '', disabled: readOnly, placeholder: 'Optional',
    });
    descriptionInput.addEventListener('input', () => {
      draft.description = descriptionInput.value;
      markDirty();
    });

    return el('div.card',
      el('div.card__header', el('h2', 'Details')),
      el('div.card__body',
        el('div.grid.grid--2',
          el('div.field', el('label.field__label', 'Name'), nameInput),
          el('div.field', el('label.field__label', 'Description'), descriptionInput)),
        el('div.row', { style: 'margin-top:14px;gap:16px;flex-wrap:wrap' },
          el('span.badge.badge--brand', `${draft.categories.length} categories`),
          el('span.badge.badge--brand', `${pointCount()} points`),
          el('span', { style: 'font-size:12.5px;color:var(--text-muted)' },
            `Version history: ${versions.map((v) => `v${v.version}${v.isPublished ? '' : ' (draft)'}`).join(', ')}`))));
  };

  const gradingCard = () => {
    const rules = draft.gradingRules;

    const pointInput = (statusKey, label) => {
      const input = el('input.input', {
        type: 'number', min: 0, max: 10, disabled: readOnly,
        value: rules.statusPoints[statusKey] ?? 0, style: 'width:84px',
      });
      input.addEventListener('input', () => {
        rules.statusPoints[statusKey] = Number(input.value || 0);
        markDirty();
      });
      return el('div.field', el('label.field__label', label), input);
    };

    const maxInput = el('input.input', {
      type: 'number', min: 1, max: 10, disabled: readOnly,
      value: rules.maxPointsPerItem, style: 'width:84px',
    });
    maxInput.addEventListener('input', () => {
      rules.maxPointsPerItem = Number(maxInput.value || 1);
      markDirty();
    });

    const bandRows = rules.bands
      .slice()
      .sort((a, b) => b.minPercentage - a.minPercentage)
      .map((band) => {
        const minInput = el('input.input', {
          type: 'number', min: 0, max: 100, value: band.minPercentage,
          disabled: readOnly, style: 'width:84px',
        });
        minInput.addEventListener('input', () => {
          band.minPercentage = Number(minInput.value || 0);
          markDirty();
        });
        const labelInput = el('input.input', { value: band.label, disabled: readOnly });
        labelInput.addEventListener('input', () => { band.label = labelInput.value; markDirty(); });

        return el('tr',
          el('td', { style: 'width:70px' }, el('strong', band.code)),
          el('td', labelInput),
          el('td', { style: 'width:120px' }, minInput),
          el('td', { style: 'width:110px;color:var(--text-muted)' }, `${band.minPercentage}% and up`));
      });

    return el('div.card',
      el('div.card__header',
        el('div',
          el('h2', 'Grading rules'),
          el('div', { style: 'font-size:12.5px;color:var(--text-muted)' },
            'Stored with the template — changing them here changes how the app scores, with no app release'))),
      el('div.card__body',
        el('div.row.row--wrap', { style: 'gap:14px;align-items:flex-end' },
          pointInput('pass', 'Pass'),
          pointInput('minor_issue', 'Minor issue'),
          pointInput('fail', 'Fail'),
          el('div.field', el('label.field__label', 'Max per point'), maxInput),
          el('div.field',
            el('label.field__label', 'Excluded'),
            el('div', { style: 'padding-top:8px;color:var(--text-muted);font-size:12.5px' },
              (rules.excludedStatuses ?? []).join(', ') || 'none'))),
        el('div', { style: 'margin-top:18px' },
          el('h3', { style: 'margin-bottom:8px' }, 'Grade bands'),
          el('div.table-wrap',
            el('table',
              el('thead', el('tr',
                el('th', 'Code'), el('th', 'Label'), el('th', 'Minimum %'), el('th', 'Range'))),
              el('tbody', ...bandRows))))));
  };

  // -------------------------------------------------------------------------
  // Structure: categories, points, drag-to-reorder
  // -------------------------------------------------------------------------

  let dragSource = null;

  const structureCard = () =>
    el('div.card',
      el('div.card__header',
        el('h2', 'Categories & points'),
        el('div.spacer'),
        !readOnly && el('button.btn.btn--sm', { type: 'button', onclick: addCategory },
          icon('plus', 15), 'Add category')),
      el('div.card__body',
        draft.categories.length
          ? el('div', ...draft.categories.map(categoryBlock))
          : emptyState('No categories', 'Add one to start building the checklist.')));

  function categoryBlock(category, categoryIndex) {
    const titleInput = el('input.input', {
      value: category.title, disabled: readOnly, style: 'max-width:260px',
    });
    titleInput.addEventListener('input', () => { category.title = titleInput.value; markDirty(); });

    const codeInput = el('input.input', {
      value: category.code, disabled: readOnly, style: 'width:84px',
    });
    codeInput.addEventListener('input', () => { category.code = codeInput.value; markDirty(); });

    return el('div.editor-category',
      el('div.editor-category__head',
        titleInput,
        codeInput,
        el('span', { style: 'font-size:12px;color:var(--text-muted)' },
          `${category.points.length} points`),
        el('div.spacer'),
        !readOnly && el('button.btn.btn--sm.btn--ghost', {
          type: 'button', title: 'Move category up', disabled: categoryIndex === 0,
          onclick: () => { moveItem(draft.categories, categoryIndex, categoryIndex - 1); },
        }, '↑'),
        !readOnly && el('button.btn.btn--sm.btn--ghost', {
          type: 'button', title: 'Move category down',
          disabled: categoryIndex === draft.categories.length - 1,
          onclick: () => { moveItem(draft.categories, categoryIndex, categoryIndex + 1); },
        }, '↓'),
        !readOnly && el('button.btn.btn--sm', { type: 'button', onclick: () => addPoint(category) },
          icon('plus', 14), 'Point'),
        !readOnly && el('button.btn.btn--sm.btn--danger.btn--icon', {
          type: 'button', title: 'Delete category',
          onclick: async () => {
            const ok = await confirmDialog('Delete category?',
              `"${category.title}" and its ${category.points.length} point(s) will be removed from this draft.`,
              'Delete');
            if (!ok) return;
            draft.categories.splice(categoryIndex, 1);
            markDirty();
            repaint();
          },
        }, icon('trash', 14))),
      el('div.editor-points',
        ...category.points.map((point, pointIndex) =>
          pointRow(category, point, pointIndex))));
  }

  function pointRow(category, point, pointIndex) {
    const codeInput = el('input.input', { value: point.code, disabled: readOnly });
    codeInput.addEventListener('input', () => { point.code = codeInput.value; markDirty(); });

    const titleInput = el('input.input', { value: point.title, disabled: readOnly });
    titleInput.addEventListener('input', () => { point.title = titleInput.value; markDirty(); });

    const row = el('div.point-row', { draggable: !readOnly },
      el('div.drag-handle', { title: 'Drag to reorder' }, icon('drag', 15)),
      codeInput,
      titleInput,
      el('div.row', { style: 'gap:4px' },
        point.isRequired
          ? el('span.badge.badge--brand', 'Required')
          : el('span.badge.badge--na', 'Optional'),
        point.requiresPhotoOnFail && el('span.badge.badge--minor', 'Photo'),
        point.weight > 1 && el('span.badge.badge--brand', `×${point.weight}`),
        !readOnly && el('button.btn.btn--sm.btn--ghost', {
          type: 'button', title: 'Point settings',
          onclick: () => editPoint(point),
        }, 'Edit'),
        !readOnly && el('button.btn.btn--sm.btn--ghost.btn--icon', {
          type: 'button', title: 'Remove point',
          onclick: () => {
            category.points.splice(pointIndex, 1);
            markDirty();
            repaint();
          },
        }, icon('trash', 14))));

    if (readOnly) return row;

    // Drag-and-drop reordering. Order is array position, so a drop is a splice.
    row.addEventListener('dragstart', () => {
      dragSource = { category, index: pointIndex };
      row.classList.add('is-dragging');
    });
    row.addEventListener('dragend', () => {
      dragSource = null;
      row.classList.remove('is-dragging');
    });
    row.addEventListener('dragover', (event) => {
      if (!dragSource) return;
      event.preventDefault();
      row.classList.add('is-over');
    });
    row.addEventListener('dragleave', () => row.classList.remove('is-over'));
    row.addEventListener('drop', (event) => {
      event.preventDefault();
      row.classList.remove('is-over');
      if (!dragSource) return;

      const [moved] = dragSource.category.points.splice(dragSource.index, 1);
      // Dropping into a different category moves the point between them, which
      // is the behaviour an admin expects from dragging across a boundary.
      category.points.splice(pointIndex, 0, moved);
      if (dragSource.category !== category) moved.categoryId = category.id;
      dragSource = null;
      markDirty();
      repaint();
    });

    return row;
  }

  function moveItem(list, from, to) {
    if (to < 0 || to >= list.length) return;
    const [moved] = list.splice(from, 1);
    list.splice(to, 0, moved);
    markDirty();
    repaint();
  }

  function addCategory() {
    const index = draft.categories.length + 1;
    const categoryId = `${draft.id}-cat-${Date.now().toString(36)}`;
    draft.categories.push({
      id: categoryId,
      code: `C${index}`,
      title: `New category ${index}`,
      iconName: 'exterior',
      points: [],
    });
    markDirty();
    repaint();
  }

  function addPoint(category) {
    const index = category.points.length + 1;
    category.points.push({
      id: `${category.id}-p-${Date.now().toString(36)}`,
      categoryId: category.id,
      code: `${category.code}-${String(index).padStart(2, '0')}`,
      title: 'New inspection point',
      description: null,
      isRequired: true,
      allowsNotApplicable: true,
      requiresPhotoOnFail: false,
      maxPhotos: 3,
      weight: 1,
    });
    markDirty();
    repaint();
  }

  async function editPoint(point) {
    const description = el('textarea.textarea', { value: point.description ?? '' });
    const required = el('input', { type: 'checkbox', checked: point.isRequired });
    const allowsNa = el('input', { type: 'checkbox', checked: point.allowsNotApplicable });
    const photoOnFail = el('input', { type: 'checkbox', checked: point.requiresPhotoOnFail });
    const maxPhotos = el('input.input', { type: 'number', min: 0, max: 10, value: point.maxPhotos });
    const weight = el('input.input', { type: 'number', min: 1, max: 10, value: point.weight });

    const saved = await modal({
      title: point.title,
      confirmLabel: 'Apply',
      body: el('div.stack',
        el('div.field',
          el('label.field__label', 'Guidance shown under the title'), description),
        el('div.grid.grid--2',
          el('div.field', el('label.field__label', 'Max photos'), maxPhotos),
          el('div.field',
            el('label.field__label', 'Weight'), weight,
            el('div.field__hint', 'A weight of 2 makes this point count double.'))),
        el('label.switch', required, 'Required — blocks submission until answered'),
        el('label.switch', allowsNa, 'Allow N/A'),
        el('label.switch', photoOnFail, 'Require a photo when marked Fail')),
      onConfirm: () => true,
    });

    if (!saved) return;
    point.description = description.value.trim() || null;
    point.isRequired = required.checked;
    point.allowsNotApplicable = allowsNa.checked;
    point.requiresPhotoOnFail = photoOnFail.checked;
    point.maxPhotos = Number(maxPhotos.value || 3);
    point.weight = Number(weight.value || 1);
    markDirty();
    repaint();
  }

  // -------------------------------------------------------------------------

  repaint();

  host.replaceChildren(el('div.stack',
    el('div.row',
      el('button.btn.btn--sm', { type: 'button', onclick: () => navigate('/templates') },
        icon('back', 15), 'Templates'),
      el('div.spacer'),
      status,
      draft.isPublished
        ? el('span.badge.badge--pass', `v${draft.version} published`)
        : el('span.badge.badge--minor', `v${draft.version} draft`),
      !readOnly && saveButton,
      !readOnly && publishButton),
    readOnly
      ? el('div.card', el('div.card__body',
          { style: 'color:var(--text-muted)' },
          'You have read-only access. Ask an admin to make changes.'))
      : null,
    body));
}
