(function () {
  'use strict';

  var THEME_KEY = 'ww-theme';
  var root = document.documentElement;

  function applyTheme(value) {
    if (value === 'light' || value === 'dark') {
      root.setAttribute('data-theme', value);
    } else {
      root.removeAttribute('data-theme');
      value = 'auto';
    }
    document.querySelectorAll('[data-theme-btn]').forEach(function (btn) {
      btn.setAttribute('aria-pressed', String(btn.getAttribute('data-theme-btn') === value));
    });
  }

  function setTheme(value) {
    try { localStorage.setItem(THEME_KEY, value); } catch (e) { /* ignore */ }
    applyTheme(value);
  }

  var savedTheme = 'auto';
  try { savedTheme = localStorage.getItem(THEME_KEY) || 'auto'; } catch (e) { /* ignore */ }
  applyTheme(savedTheme);

  document.querySelectorAll('[data-theme-btn]').forEach(function (btn) {
    btn.addEventListener('click', function () { setTheme(btn.getAttribute('data-theme-btn')); });
  });

  // ---------- Hero time-of-day switcher ----------

  var TIME_LABELS = { sunrise: 'Sunrise', day: 'Day', sunset: 'Sunset', night: 'Night' };

  function defaultTimeOfDay() {
    var hour = new Date().getHours();
    if (hour >= 5 && hour < 8) return 'sunrise';
    if (hour >= 8 && hour < 18) return 'day';
    if (hour >= 18 && hour < 21) return 'sunset';
    return 'night';
  }

  function setTimeOfDay(value) {
    document.querySelectorAll('[data-sky]').forEach(function (el) {
      el.classList.toggle('is-active', el.getAttribute('data-sky') === value);
    });
    document.querySelectorAll('[data-time-btn]').forEach(function (btn) {
      btn.setAttribute('aria-pressed', String(btn.getAttribute('data-time-btn') === value));
    });
    var label = document.querySelector('[data-time-label]');
    if (label) label.textContent = TIME_LABELS[value];
  }

  document.querySelectorAll('[data-time-btn]').forEach(function (btn) {
    btn.addEventListener('click', function () { setTimeOfDay(btn.getAttribute('data-time-btn')); });
  });

  setTimeOfDay(defaultTimeOfDay());

  // ---------- Live lock-screen date ----------

  var dateEl = document.querySelector('[data-lock-date]');
  if (dateEl) {
    dateEl.textContent = new Date().toLocaleDateString(undefined, {
      weekday: 'long', month: 'long', day: 'numeric',
    });
  }
})();
