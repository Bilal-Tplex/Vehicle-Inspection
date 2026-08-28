import { api, session, setUnauthorizedHandler } from './api.js';
import { currentPath, defineRoutes, navigate, resolve, startRouter } from './router.js';
import { el, emptyState, fmt, icon, toast } from './ui.js';
import { renderInspectionDetail } from './views/inspection-detail.js';
import { renderInspections } from './views/inspections.js';
import { renderLogin } from './views/login.js';
import { renderOverview } from './views/overview.js';
import { renderReports } from './views/reports.js';
import { renderTemplateEditor } from './views/template-editor.js';
import { renderTemplates } from './views/templates.js';
import { renderUsers } from './views/users.js';

const root = document.getElementById('root');

const THEME_KEY = 'vi.dashboard.theme';

function applyTheme(theme) {
  document.documentElement.dataset.theme = theme;
  localStorage.setItem(THEME_KEY, theme);
}
applyTheme(localStorage.getItem(THEME_KEY) ?? 'light');

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

const NAV = [
  { path: '/', label: 'Overview', iconName: 'overview' },
  { path: '/inspections', label: 'Inspections', iconName: 'inspections' },
  { path: '/templates', label: 'Templates', iconName: 'templates' },
  { path: '/users', label: 'Evaluators & roles', iconName: 'users' },
  { path: '/reports', label: 'Reports', iconName: 'reports' },
];

const PAGE_META = {
  '/': ['Overview', 'Everything arriving from the field, at a glance'],
  '/inspections': ['Inspections', 'Search, review and export submitted inspections'],
  '/inspections/:id': ['Inspection', 'Full checklist, media and review'],
  '/templates': ['Templates', 'The checklists the mobile app pulls'],
  '/templates/:id': ['Template editor', 'Points, ordering and grading rules'],
  '/users': ['Evaluators & roles', 'Who can capture, review and administer'],
  '/reports': ['Reports', 'Aggregates, defect trends and the activity log'],
};

defineRoutes({
  '/': renderOverview,
  '/inspections': renderInspections,
  '/inspections/:id': renderInspectionDetail,
  '/templates': renderTemplates,
  '/templates/:id': renderTemplateEditor,
  '/users': renderUsers,
  '/reports': renderReports,
});

// ---------------------------------------------------------------------------
// Shell
// ---------------------------------------------------------------------------

let shell = null;

function buildShell() {
  const user = session.user;
  const content = el('main.content');
  const pageTitle = el('h1');
  const pageHint = el('div.topbar__meta');
  const navLinks = new Map();

  const sidebar = el('aside.sidebar',
    el('div.sidebar__brand',
      el('div.sidebar__logo', icon('car', 19)),
      el('div',
        el('div.sidebar__title', 'Vehicle Inspection'),
        el('div.sidebar__subtitle', 'Admin Dashboard'))),
    el('nav.sidebar__nav',
      el('div.sidebar__section', 'Workspace'),
      ...NAV.map((item) => {
        const link = el('a.navlink', { href: `#${item.path}` }, icon(item.iconName), item.label);
        navLinks.set(item.path, link);
        return link;
      })),
    el('div.sidebar__footer',
      el('div.userchip',
        el('div.avatar', fmt.initials(user?.name)),
        el('div', { style: 'min-width:0' },
          el('div.userchip__name', user?.name ?? ''),
          el('div.userchip__role', user?.role ?? ''))),
      el('button.navlink', {
        type: 'button',
        onclick: async () => {
          await api.logout();
          render();
          toast('Signed out');
        },
      }, icon('logout'), 'Sign out')));

  const themeButton = el('button.btn.btn--icon', {
    type: 'button', title: 'Toggle theme',
    onclick: () => {
      const next = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
      applyTheme(next);
      themeButton.replaceChildren(icon(next === 'dark' ? 'sun' : 'moon', 16));
    },
  }, icon(document.documentElement.dataset.theme === 'dark' ? 'sun' : 'moon', 16));

  const menuButton = el('button.btn.btn--icon.menu-toggle', {
    type: 'button', onclick: () => sidebar.classList.toggle('is-open'),
  }, icon('menu', 16));

  const app = el('div.app',
    sidebar,
    el('div.main',
      el('header.topbar',
        el('div.row', menuButton, el('div', pageTitle, pageHint)),
        el('div.row', themeButton)),
      content));

  return { app, content, pageTitle, pageHint, navLinks, sidebar };
}

function highlight(path) {
  for (const [routePath, link] of shell.navLinks) {
    const active = routePath === '/'
      ? path === '/'
      : path === routePath || path.startsWith(`${routePath}/`);
    link.classList.toggle('is-active', active);
  }
}

async function renderRoute(path) {
  const match = resolve(path);

  if (!match) {
    shell.pageTitle.textContent = 'Not found';
    shell.pageHint.textContent = '';
    shell.content.replaceChildren(
      emptyState('That page does not exist', `Nothing is routed to "${path}".`,
        el('button.btn.btn--primary', { type: 'button', onclick: () => navigate('/') }, 'Go to overview')),
    );
    return;
  }

  const [title, hint] = PAGE_META[match.route.pattern] ?? ['', ''];
  shell.pageTitle.textContent = title;
  shell.pageHint.textContent = hint;
  shell.sidebar.classList.remove('is-open');
  highlight(path);

  try {
    await match.route.view(shell.content, match.params);
  } catch (error) {
    console.error(error);
    shell.content.replaceChildren(
      emptyState('Something went wrong rendering this page', error.message),
    );
  }
}

// ---------------------------------------------------------------------------
// Bootstrap
// ---------------------------------------------------------------------------

let routerStarted = false;

function render() {
  if (!session.token) {
    shell = null;
    root.replaceChildren(renderLogin(() => render()));
    return;
  }

  shell = buildShell();
  root.replaceChildren(shell.app);

  if (routerStarted) renderRoute(currentPath());
  else {
    startRouter(renderRoute);
    routerStarted = true;
  }
}

// A rejected token anywhere in the app drops straight back to the login screen.
setUnauthorizedHandler(() => {
  shell = null;
  root.replaceChildren(renderLogin(() => render()));
});

render();
