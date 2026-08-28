import { api } from '../api.js';
import { el, icon } from '../ui.js';

/** Sign-in screen. Rendered instead of the shell when there is no session. */
export function renderLogin(onSuccess) {
  const emailInput = el('input.input', {
    type: 'email', value: 'admin@test.com', autocomplete: 'username', required: true,
  });
  const passwordInput = el('input.input', {
    type: 'password', value: 'admin123', autocomplete: 'current-password', required: true,
  });
  const error = el('div.field__error', { style: 'display:none' });
  const submit = el('button.btn.btn--primary', { type: 'submit', style: 'width:100%' }, 'Sign in');

  const form = el('form', {
    onsubmit: async (event) => {
      event.preventDefault();
      error.style.display = 'none';
      submit.disabled = true;
      submit.textContent = 'Signing in...';
      try {
        onSuccess(await api.login(emailInput.value.trim(), passwordInput.value));
      } catch (failure) {
        error.textContent = failure.message;
        error.style.display = 'block';
        submit.disabled = false;
        submit.textContent = 'Sign in';
      }
    },
  },
    el('div.stack',
      el('div.field', el('label.field__label', 'Email'), emailInput),
      el('div.field', el('label.field__label', 'Password'), passwordInput),
      error,
      submit));

  return el('div.login',
    el('div.login__card',
      el('div.login__head',
        el('div.login__logo', icon('car', 27)),
        el('h1', 'Vehicle Inspection'),
        el('div', { style: 'color:var(--text-muted);margin-top:4px' }, 'Admin Dashboard')),
      el('div.card', el('div.card__body', form)),
      el('div.login__hint',
        el('div', { style: 'font-weight:600;color:var(--text);margin-bottom:5px' }, 'Demo accounts'),
        el('div', 'admin@test.com / admin123 — full access'),
        el('div', 'reviewer@test.com / reviewer123 — read only'),
        el('div', { style: 'margin-top:7px;color:var(--text-faint)' },
          'Evaluators sign in through the mobile app, not here.'))));
}
