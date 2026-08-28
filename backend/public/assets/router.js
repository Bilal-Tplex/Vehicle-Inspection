/**
 * Hash-based router.
 *
 * Hash routing rather than the History API so the dashboard can be served from
 * any path without server rewrites, and so a deep link survives a hard refresh.
 */

const routes = [];
let onNavigate = () => {};

/** `/inspections/:id` -> regex plus the parameter names it captures. */
function compile(pattern) {
  const names = [];
  const source = pattern
    .replace(/\/:([^/]+)/g, (_, name) => {
      names.push(name);
      return '/([^/]+)';
    })
    .replace(/\//g, '\\/');
  return { regex: new RegExp(`^${source}$`), names };
}

export function defineRoutes(definitions) {
  routes.length = 0;
  for (const [pattern, view] of Object.entries(definitions)) {
    routes.push({ pattern, view, ...compile(pattern) });
  }
}

export function resolve(path) {
  for (const route of routes) {
    const match = route.regex.exec(path);
    if (!match) continue;
    const params = Object.fromEntries(
      route.names.map((name, index) => [name, decodeURIComponent(match[index + 1])]),
    );
    return { route, params };
  }
  return null;
}

export const currentPath = () => window.location.hash.slice(1) || '/';

export function navigate(path, { replace = false } = {}) {
  const target = `#${path}`;
  if (window.location.hash === target) return;
  if (replace) window.location.replace(target);
  else window.location.hash = target;
}

export function startRouter(handler) {
  onNavigate = handler;
  window.addEventListener('hashchange', () => onNavigate(currentPath()));
  onNavigate(currentPath());
}
