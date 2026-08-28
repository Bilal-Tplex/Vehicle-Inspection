/**
 * Thin API client for the dashboard.
 *
 * Holds the bearer token, normalises errors into a single `ApiError` shape, and
 * signs out automatically on a 401 so an expired session cannot leave the UI
 * showing stale data it can no longer refresh.
 */

const BASE = '/v1';
const TOKEN_KEY = 'vi.dashboard.token';
const USER_KEY = 'vi.dashboard.user';

export class ApiError extends Error {
  constructor(status, message, details) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

export const session = {
  get token() {
    return localStorage.getItem(TOKEN_KEY);
  },
  get user() {
    try {
      return JSON.parse(localStorage.getItem(USER_KEY) ?? 'null');
    } catch {
      return null;
    }
  },
  save(token, user) {
    localStorage.setItem(TOKEN_KEY, token);
    localStorage.setItem(USER_KEY, JSON.stringify(user));
  },
  clear() {
    localStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem(USER_KEY);
  },
  get isAdmin() {
    return this.user?.role === 'admin';
  },
};

/** Called when the server rejects our token. Set by app.js. */
let onUnauthorized = () => {};
export const setUnauthorizedHandler = (fn) => {
  onUnauthorized = fn;
};

async function request(path, { method = 'GET', body, raw = false } = {}) {
  const headers = {};
  if (session.token) headers.Authorization = `Bearer ${session.token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';

  const response = await fetch(`${BASE}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });

  if (response.status === 401) {
    session.clear();
    onUnauthorized();
    throw new ApiError(401, 'Your session has expired. Please sign in again.');
  }

  if (!response.ok) {
    // Error responses are JSON by contract, but a proxy or crash could return
    // HTML — fall back to the status text rather than throwing while throwing.
    let payload = null;
    try {
      payload = await response.json();
    } catch {
      /* ignore */
    }
    throw new ApiError(
      response.status,
      payload?.error?.message ?? response.statusText ?? 'Request failed',
      payload?.error?.details,
    );
  }

  if (raw) return response;
  if (response.status === 204) return null;
  return response.json();
}

export const api = {
  get: (path) => request(path),
  post: (path, body) => request(path, { method: 'POST', body }),
  put: (path, body) => request(path, { method: 'PUT', body }),
  patch: (path, body) => request(path, { method: 'PATCH', body }),
  delete: (path) => request(path, { method: 'DELETE' }),

  async login(email, password) {
    const data = await request('/auth/login', {
      method: 'POST',
      body: { email, password },
    });
    if (!['admin', 'reviewer'].includes(data.user.role)) {
      throw new ApiError(
        403,
        'Evaluator accounts sign in through the mobile app, not the dashboard.',
      );
    }
    session.save(data.accessToken, data.user);
    return data.user;
  },

  async logout() {
    try {
      await request('/auth/logout', { method: 'POST' });
    } catch {
      // Signing out locally matters more than telling the server about it.
    }
    session.clear();
  },

  /**
   * Media needs the auth header, so it cannot be an `<img src>` directly.
   * Fetch as a blob and hand back an object URL.
   */
  async media(path) {
    const response = await request(path.replace(BASE, ''), { raw: true });
    const blob = await response.blob();
    return URL.createObjectURL(blob);
  },

  /** Triggers a browser download for an authenticated endpoint. */
  async download(path, filename) {
    const response = await request(path, { raw: true });
    const blob = await response.blob();
    const url = URL.createObjectURL(blob);
    const link = Object.assign(document.createElement('a'), { href: url, download: filename });
    document.body.append(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  },
};
