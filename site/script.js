(function () {
  'use strict';

  var THEME_KEY = 'ww-theme';
  var root = document.documentElement;
  var THEME_ORDER = ['auto', 'light', 'dark'];
  var THEME_ICON = { auto: '◐', light: '☀', dark: '☾' };
  var THEME_LABEL = { auto: 'Auto', light: 'Light', dark: 'Dark' };

  function applyTheme(value) {
    if (value === 'light' || value === 'dark') {
      root.setAttribute('data-theme', value);
    } else {
      root.removeAttribute('data-theme');
      value = 'auto';
    }
    var btn = document.querySelector('[data-theme-cycle]');
    if (btn) {
      btn.textContent = THEME_ICON[value];
      btn.title = 'Theme: ' + THEME_LABEL[value];
      btn.setAttribute('aria-label', 'Theme: ' + THEME_LABEL[value] + ' (click to change)');
    }
  }

  function setTheme(value) {
    try { localStorage.setItem(THEME_KEY, value); } catch (e) { /* ignore */ }
    applyTheme(value);
  }

  var savedTheme = 'auto';
  try { savedTheme = localStorage.getItem(THEME_KEY) || 'auto'; } catch (e) { /* ignore */ }
  if (THEME_ORDER.indexOf(savedTheme) === -1) savedTheme = 'auto';
  applyTheme(savedTheme);

  var themeCycleBtn = document.querySelector('[data-theme-cycle]');
  if (themeCycleBtn) {
    themeCycleBtn.addEventListener('click', function () {
      var current = root.getAttribute('data-theme') || 'auto';
      var next = THEME_ORDER[(THEME_ORDER.indexOf(current) + 1) % THEME_ORDER.length];
      setTheme(next);
    });
  }

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

  // ---------- Hero weather switcher ----------

  var WEATHER_ICON = { clear: '☀', cloudy: '⛅', rain: '🌧', snow: '❄' };
  var WEATHER_LABEL = { clear: 'Clear', cloudy: 'Cloudy', rain: 'Rain', snow: 'Snow' };

  function setWeather(value) {
    var fx = document.querySelector('[data-weather-fx]');
    if (fx) {
      fx.setAttribute('data-weather-fx', value);
      fx.classList.toggle('is-active', value !== 'clear');
    }
    document.querySelectorAll('[data-weather-btn]').forEach(function (btn) {
      btn.setAttribute('aria-pressed', String(btn.getAttribute('data-weather-btn') === value));
    });
    var icon = document.querySelector('[data-weather-icon]');
    var label = document.querySelector('[data-weather-label]');
    if (icon) icon.textContent = WEATHER_ICON[value];
    if (label) label.textContent = WEATHER_LABEL[value];
  }

  document.querySelectorAll('[data-weather-btn]').forEach(function (btn) {
    btn.addEventListener('click', function () { setWeather(btn.getAttribute('data-weather-btn')); });
  });

  setWeather('clear');

  // ---------- Live lock-screen date ----------

  var dateEl = document.querySelector('[data-lock-date]');
  if (dateEl) {
    dateEl.textContent = new Date().toLocaleDateString(undefined, {
      weekday: 'long', month: 'long', day: 'numeric',
    });
  }

  // ---------- GitHub star count ----------

  fetch('https://api.github.com/repos/mekedron/WeatherWallpapers')
    .then(function (res) { return res.ok ? res.json() : null; })
    .then(function (data) {
      if (!data || typeof data.stargazers_count !== 'number') return;
      var el = document.querySelector('[data-star-count]');
      if (!el) return;
      var count = data.stargazers_count;
      el.textContent = count >= 1000 ? (count / 1000).toFixed(1).replace(/\.0$/, '') + 'k' : String(count);
      el.hidden = false;
    })
    .catch(function () { /* offline or rate-limited — leave it hidden */ });
})();
