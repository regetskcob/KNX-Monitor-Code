// Busclear – dashboard card "Busclear Diagramm" (custom:knx-monitor-chart-card).
//
// Shows a chart saved in the app on the Home Assistant dashboard.
// The add-on puts this file into /config/www/knx-monitor/ on every start
// and fills in the placeholders (server/lib/src/lovelace_card.dart); the values
// come via Ingress from the add-on's history (/api/charts/series).
//
// No build step and no dependencies: a web component that draws
// SVG. Colours as in the app (Palette.series), text and grid from the
// Home Assistant theme.

const INGRESS = '__KNX_MONITOR_INGRESS__';
const VERSION = '__KNX_MONITOR_VERSION__';
const CARD = 'knx-monitor-chart-card';

/** Time ranges in hours, as in the app. */
const RANGES = [1, 6, 24, 168];

/** Reload while the card is visible. */
const REFRESH_MS = 60 * 1000;

/** Series colours like the app's Palette.series; the first is the accent "Bus". */
const SERIES = {
  light: ['#437F18', '#3D75AC', '#B96462', '#31518C', '#B18334', '#006640', '#7A5B9C', '#7C9B53', '#873F5E', '#008C99'],
  dark: ['#9BD45E', '#73A9E1', '#E3918E', '#5779B8', '#D3A65D', '#3D936A', '#A788CA', '#A2C17B', '#B76A89', '#38B1BD'],
};

const TEXT = {
  de: {
    name: 'Busclear Diagramm',
    description: 'Ein in Busclear gespeichertes Diagramm, direkt aus dem Busverlauf.',
    chart: 'Diagramm',
    hours: 'Zeitraum',
    title: 'Titel (optional)',
    range: { 1: '1 h', 6: '6 h', 24: '24 h', 168: '7 T' },
    loading: 'Lade …',
    noChart: 'Wähle in den Karteneinstellungen ein Diagramm.',
    noCharts: 'Noch keine Diagramme. Lege sie im Busclear unter „Diagramme“ an.',
    notFound: (n) => `Das Diagramm „${n}“ gibt es im Busclear nicht mehr.`,
    locked: 'Diagramme im Dashboard gehören zu Busclear Plus.',
    empty: 'Keine Werte in diesem Zeitraum.',
    error: (d) => `Busclear nicht erreichbar (${d}).`,
  },
  en: {
    name: 'Busclear chart',
    description: 'A chart saved in Busclear, straight from the bus history.',
    chart: 'Chart',
    hours: 'Time range',
    title: 'Title (optional)',
    range: { 1: '1 h', 6: '6 h', 24: '24 h', 168: '7 d' },
    loading: 'Loading …',
    noChart: 'Choose a chart in the card settings.',
    noCharts: 'No charts yet. Create them in Busclear under “Charts”.',
    notFound: (n) => `The chart “${n}” no longer exists in Busclear.`,
    locked: 'Charts on dashboards are part of Busclear Plus.',
    empty: 'No values in this time range.',
    error: (d) => `Busclear not reachable (${d}).`,
  },
};

const text = (hass) => (String(hass?.locale?.language ?? hass?.language ?? 'en').startsWith('de') ? TEXT.de : TEXT.en);

const esc = (s) =>
  String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

// --- Access via Ingress ---------------------------------------------------------------

class ApiError extends Error {
  constructor(kind, detail) {
    super(detail ? `${kind} ${detail}` : kind);
    this.kind = kind;
    this.detail = detail;
  }
}

/** One Ingress session for all cards on the page (Supervisor, valid for 15 min). */
let session = null;
const SESSION_MS = 5 * 60 * 1000;

async function ingressSession(hass, force) {
  if (!force && session && Date.now() - session.at < SESSION_MS) return session.ready;
  const ready = hass
    .callWS({ type: 'supervisor/api', endpoint: '/ingress/session', method: 'post' })
    .then((r) => {
      const secure = location.protocol === 'https:' ? ';Secure' : '';
      document.cookie = `ingress_session=${r.session};path=/api/hassio_ingress/;SameSite=Strict${secure}`;
    });
  session = { at: Date.now(), ready };
  ready.catch(() => {
    if (session?.ready === ready) session = null;
  });
  return ready;
}

/** GET [path] from the add-on; renews the session once if it has expired. */
async function api(hass, path) {
  if (INGRESS.startsWith('__')) throw new ApiError('setup');
  for (const retry of [false, true]) {
    try {
      await ingressSession(hass, retry);
    } catch (e) {
      throw new ApiError('session', e?.message ?? e?.code ?? '');
    }
    const res = await fetch(`${INGRESS}${path}`, { credentials: 'same-origin', cache: 'no-store' });
    if (res.ok) return res.json();
    if (res.status === 404) throw new ApiError('notFound');
    if (!retry && (res.status === 401 || res.status === 403)) continue;
    throw new ApiError('http', `HTTP ${res.status}`);
  }
  throw new ApiError('http');
}

// --- Value labels --------------------------------------------------------------------

function formatValue(hass, series, v) {
  if (series.kind === 'step') return v >= 0.5 ? series.on ?? '1' : series.off ?? '0';
  const abs = Math.abs(v);
  const digits = abs >= 100 ? 0 : abs >= 10 ? 1 : 2;
  const n = new Intl.NumberFormat(hass?.locale?.language ?? undefined, { maximumFractionDigits: digits }).format(v);
  return series.unit ? `${n} ${series.unit}` : n;
}

/** Time of day; [day]: only the day (axis over days), [weekday]: day and time. */
function formatTime(hass, ms, { day = false, weekday = false } = {}) {
  const options = day
    ? { weekday: 'short', day: 'numeric' }
    : weekday
      ? { weekday: 'short', hour: '2-digit', minute: '2-digit' }
      : { hour: '2-digit', minute: '2-digit' };
  return new Intl.DateTimeFormat(hass?.locale?.language ?? undefined, options).format(new Date(ms));
}

const seriesName = (s) => s.name || s.label;

/** Round axis steps (1, 2, 5 × 10^n). */
function niceTicks(min, max, count) {
  const span = max - min || 1;
  const raw = span / Math.max(1, count);
  const mag = 10 ** Math.floor(Math.log10(raw));
  const step = [1, 2, 5, 10].map((m) => m * mag).find((s) => s >= raw) ?? 10 * mag;
  const ticks = [];
  for (let t = Math.ceil(min / step) * step; t <= max + step * 1e-9; t += step) ticks.push(Number(t.toFixed(10)));
  return ticks;
}

/** Spacing of the time ticks in minutes. */
const TIME_STEPS = [5, 15, 30, 60, 120, 180, 360, 720, 1440];

/** Time ticks at round local times (midnight, full hours), also across DST changes. */
function timeTicks(from, to, minutes) {
  const ticks = [];
  const d = new Date(from);
  d.setSeconds(0, 0);
  d.setMinutes(Math.ceil(d.getMinutes() / 5) * 5);
  for (; d.getTime() <= to; d.setMinutes(d.getMinutes() + 5)) {
    if ((d.getHours() * 60 + d.getMinutes()) % minutes === 0) ticks.push(d.getTime());
  }
  return ticks;
}

/** Value of a series at time [t]: the last one sent (KNX values hold until the next). */
function valueAt(series, t) {
  const pts = series.points;
  if (!pts.length) return null;
  let lo = 0;
  let hi = pts.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (pts[mid][0] <= t) lo = mid;
    else hi = mid - 1;
  }
  return pts[lo][0] <= t ? pts[lo] : null;
}

// --- Card ----------------------------------------------------------------------------

const STYLE = `
  :host { display: block; }
  ha-card { padding: 12px 16px 12px; overflow: hidden; }
  .head { display: flex; align-items: center; gap: 8px; min-height: 28px; }
  .title { flex: 1; font-size: 16px; font-weight: 500; color: var(--primary-text-color);
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .ranges { display: flex; gap: 2px; }
  .ranges button { font: inherit; font-size: 12px; padding: 2px 8px; border-radius: 6px; cursor: pointer;
    border: 1px solid transparent; background: none; color: var(--secondary-text-color); min-height: 24px; }
  .ranges button[aria-pressed="true"] { border-color: var(--divider-color); color: var(--primary-text-color); }
  .legend { display: flex; flex-wrap: wrap; gap: 4px 14px; margin: 6px 0 4px; font-size: 13px; }
  .legend span { display: inline-flex; align-items: center; gap: 6px; color: var(--secondary-text-color); }
  .legend i { width: 12px; height: 3px; border-radius: 2px; display: inline-block; }
  .legend b { font-weight: 500; color: var(--primary-text-color); font-variant-numeric: tabular-nums; }
  .plot { position: relative; touch-action: pan-y; }
  svg { display: block; width: 100%; overflow: visible; }
  svg text { font-size: 11px; fill: var(--secondary-text-color); font-variant-numeric: tabular-nums; }
  svg text.lane { fill: var(--primary-text-color); pointer-events: none; }
  .note { color: var(--secondary-text-color); font-size: 14px; padding: 16px 0 8px; }
  .tip { position: absolute; pointer-events: none; background: var(--card-background-color, #fff);
    border: 1px solid var(--divider-color); border-radius: 8px; padding: 6px 8px; font-size: 12px;
    color: var(--primary-text-color); white-space: nowrap; box-shadow: 0 2px 6px rgba(0,0,0,.12); z-index: 1; }
  .tip div { display: flex; align-items: center; gap: 6px; }
  .tip i { width: 8px; height: 8px; border-radius: 2px; display: inline-block; }
  .tip .time { color: var(--secondary-text-color); margin-bottom: 2px; }
`;

class KnxMonitorChartCard extends HTMLElement {
  static getStubConfig() {
    return { chart: '', hours: 24 };
  }

  static getConfigElement() {
    return document.createElement(`${CARD}-editor`);
  }

  constructor() {
    super();
    this.attachShadow({ mode: 'open' });
    this._data = null;
    this._error = null;
    this._width = 0;
  }

  setConfig(config) {
    if (!config || typeof config !== 'object') throw new Error('Invalid configuration');
    const hours = Number(config.hours) || 24;
    const changed = !this._config || this._config.chart !== config.chart || this._config.hours !== config.hours;
    this._config = { ...config, hours: RANGES.includes(hours) ? hours : 24 };
    if (changed) {
      this._hours = this._config.hours;
      this._data = null;
      this._error = null;
      if (this._hass) this._load();
    }
    this._render();
  }

  set hass(hass) {
    const first = !this._hass;
    const dark = !!hass?.themes?.darkMode;
    const redraw = first || dark !== this._dark;
    this._hass = hass;
    this._dark = dark;
    if (first) this._load();
    else if (redraw) this._render();
  }

  getCardSize() {
    return 4;
  }

  getGridOptions() {
    return { columns: 12, min_columns: 6, rows: 'auto' };
  }

  connectedCallback() {
    this._timer = setInterval(() => {
      if (document.visibilityState === 'visible') this._load();
    }, REFRESH_MS);
    this._resize = new ResizeObserver(() => {
      const w = this.shadowRoot.querySelector('.plot')?.clientWidth ?? 0;
      if (w && Math.abs(w - this._width) > 1) this._render();
    });
    this._resize.observe(this);
    if (this._hass && this._config) this._load();
  }

  disconnectedCallback() {
    clearInterval(this._timer);
    this._resize?.disconnect();
  }

  async _load() {
    const chart = this._config?.chart;
    if (!this._hass || !chart) return this._render();
    const ticket = (this._ticket = (this._ticket ?? 0) + 1);
    try {
      const data = await api(this._hass, `/api/charts/series?name=${encodeURIComponent(chart)}&hours=${this._hours}`);
      if (ticket !== this._ticket) return;
      this._data = data;
      this._error = null;
    } catch (e) {
      if (ticket !== this._ticket) return;
      this._error = e;
    }
    this._render();
  }

  _render() {
    if (!this._config) return;
    const t = text(this._hass);
    const title = this._config.title || this._config.chart || t.name;
    const ranges = RANGES.map(
      (h) => `<button type="button" data-h="${h}" aria-pressed="${h === this._hours}">${esc(t.range[h])}</button>`,
    ).join('');
    let body;
    const data = this._data;
    if (!this._config.chart) body = `<div class="note">${esc(t.noChart)}</div>`;
    else if (this._error?.kind === 'notFound') body = `<div class="note">${esc(t.notFound(this._config.chart))}</div>`;
    else if (this._error && !data) body = `<div class="note">${esc(t.error(this._error.detail || this._error.kind))}</div>`;
    else if (!data) body = `<div class="note">${esc(t.loading)}</div>`;
    else if (data.allowed === false) body = `<div class="note">${esc(t.locked)}</div>`;
    else body = `<div class="legend"></div><div class="plot"><svg></svg></div>`;
    this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card>
      <div class="head"><div class="title" title="${esc(title)}">${esc(title)}</div>
      ${this._config.chart ? `<div class="ranges" role="group">${ranges}</div>` : ''}</div>${body}</ha-card>`;
    for (const b of this.shadowRoot.querySelectorAll('.ranges button')) {
      b.addEventListener('click', () => {
        this._hours = Number(b.dataset.h);
        this._render();
        this._load();
      });
    }
    if (data && data.allowed !== false && this.shadowRoot.querySelector('.plot')) this._draw(data);
  }

  _draw(data) {
    const t = text(this._hass);
    const hass = this._hass;
    const colors = this._dark ? SERIES.dark : SERIES.light;
    const series = data.series.map((s, i) => ({ ...s, points: s.points ?? [], color: colors[i % colors.length] }));
    const legend = this.shadowRoot.querySelector('.legend');
    legend.innerHTML = series
      .map((s) => {
        const last = s.last ? formatValue(hass, s, s.last[1]) : '–';
        return `<span title="${esc(`${s.label} ${s.name ?? ''}`.trim())}"><i style="background:${s.color}"></i>${esc(
          seriesName(s),
        )} <b>${esc(last)}</b></span>`;
      })
      .join('');
    const plot = this.shadowRoot.querySelector('.plot');
    const svg = plot.querySelector('svg');
    if (!series.some((s) => s.points.length)) {
      plot.innerHTML = `<div class="note">${esc(t.empty)}</div>`;
      return;
    }

    // Numbers per unit in their own area, switch states as narrow bands (like the app).
    const groups = new Map();
    const lanes = [];
    for (const s of series) {
      if (s.kind === 'step') lanes.push(s);
      else {
        const key = s.unit ?? '';
        if (!groups.has(key)) groups.set(key, []);
        groups.get(key).push(s);
      }
    }
    const width = plot.clientWidth || 300;
    this._width = width;
    const left = 44;
    const right = 8;
    const w = Math.max(10, width - left - right);
    const from = data.from;
    const to = data.to;
    const x = (ms) => left + ((ms - from) / (to - from)) * w;
    const panelH = groups.size > 1 ? 100 : 140;
    const laneH = 22;
    const unitH = 14;
    const gap = 10;
    let y0 = 4;
    const parts = [];
    const grid = 'var(--divider-color)';

    for (const [unit, list] of groups) {
      const values = list.flatMap((s) => s.points.map((p) => p[1]));
      if (!values.length) continue;
      let min = Math.min(...values);
      let max = Math.max(...values);
      if (min === max) {
        min -= 1;
        max += 1;
      }
      const pad = (max - min) * 0.08;
      min -= pad;
      max += pad;
      const ticks = niceTicks(min, max, 3);
      // Unit above the area, not on the topmost number.
      if (unit) parts.push(`<text x="${left - 6}" y="${y0 + 9}" text-anchor="end">${esc(unit)}</text>`);
      y0 += unitH;
      const y = (v) => y0 + panelH - ((v - min) / (max - min)) * panelH;
      for (const tick of ticks) {
        parts.push(`<line x1="${left}" x2="${left + w}" y1="${y(tick)}" y2="${y(tick)}" stroke="${grid}" stroke-width="1"/>`);
        const label = formatValue(hass, { kind: 'line', unit: '' }, tick);
        parts.push(`<text x="${left - 6}" y="${y(tick) + 4}" text-anchor="end">${esc(label)}</text>`);
      }
      for (const s of list) {
        if (!s.points.length) continue;
        // Steps: a KNX value holds until the next telegram arrives.
        const d = s.points
          .map((p, i) => {
            const px = x(p[0]).toFixed(1);
            const py = y(p[1]).toFixed(1);
            return i ? `H${px}V${py}` : `M${px},${py}`;
          })
          .join('');
        parts.push(`<path d="${d}" fill="none" stroke="${s.color}" stroke-width="1.75" stroke-linejoin="round"/>`);
        // The last value holds until now (KNX sends on change).
        const last = s.points[s.points.length - 1];
        parts.push(
          `<line x1="${x(last[0])}" x2="${x(to)}" y1="${y(last[1])}" y2="${y(last[1])}" stroke="${s.color}" stroke-width="1.75" stroke-dasharray="3 3" opacity="0.6"/>`,
        );
      }
      y0 += panelH + gap;
    }
    for (const s of lanes) {
      parts.push(`<line x1="${left}" x2="${left + w}" y1="${y0 + laneH}" y2="${y0 + laneH}" stroke="${grid}" stroke-width="1"/>`);
      const pts = s.points;
      for (let i = 0; i < pts.length; i++) {
        if (pts[i][1] < 0.5) continue;
        const end = i + 1 < pts.length ? pts[i + 1][0] : to;
        const x1 = x(pts[i][0]);
        // Tinted with a full top edge (like the app), so that the name stays readable.
        const bw = Math.max(1.5, x(end) - x1);
        parts.push(`<rect x="${x1}" y="${y0 + 2}" width="${bw}" height="${laneH - 2}" fill="${s.color}" opacity="0.3"/>`);
        parts.push(`<line x1="${x1}" x2="${x1 + bw}" y1="${y0 + 2}" y2="${y0 + 2}" stroke="${s.color}" stroke-width="2"/>`);
      }
      // On the left the current state, the name in the band.
      const state = s.last ? formatValue(hass, s, s.last[1]) : '';
      parts.push(`<text x="${left - 6}" y="${y0 + laneH - 6}" text-anchor="end">${esc(state)}</text>`);
      parts.push(`<text class="lane" x="${left + 6}" y="${y0 + laneH - 6}">${esc(seriesName(s))}</text>`);
      y0 += laneH + gap;
    }
    // Time axis
    const hours = (to - from) / 3600000;
    const maxTicks = Math.max(2, Math.floor(w / 80));
    const minutes = TIME_STEPS.find((m) => (to - from) / (m * 60000) <= maxTicks) ?? TIME_STEPS.at(-1);
    // Too many days for the width: show every second (third …) one.
    const all = timeTicks(from, to, minutes);
    const every = Math.ceil(all.length / maxTicks);
    for (const ms of all.filter((_, i) => i % every === 0)) {
      if (x(ms) < left + 12 || x(ms) > left + w - 12) continue;
      parts.push(`<line x1="${x(ms)}" x2="${x(ms)}" y1="${y0 - gap}" y2="${y0 - gap + 4}" stroke="${grid}"/>`);
      parts.push(`<text x="${x(ms)}" y="${y0 + 6}" text-anchor="middle">${esc(formatTime(hass, ms, { day: minutes >= 1440 }))}</text>`);
    }
    const height = y0 + 10;
    svg.setAttribute('viewBox', `0 0 ${width} ${height}`);
    svg.setAttribute('height', height);
    svg.innerHTML = `${parts.join('')}<line class="cursor" y1="0" y2="${y0 - gap}" stroke="var(--secondary-text-color)" stroke-width="1" visibility="hidden"/>`;

    // Finger or mouse shows the values at this position.
    const cursor = svg.querySelector('.cursor');
    const tip = document.createElement('div');
    tip.className = 'tip';
    tip.hidden = true;
    plot.appendChild(tip);
    const show = (event) => {
      const rect = svg.getBoundingClientRect();
      const px = event.clientX - rect.left;
      if (px < left || px > left + w) return hide();
      const ms = from + ((px - left) / w) * (to - from);
      const rows = series
        .map((s) => [s, valueAt(s, ms)])
        .filter(([, p]) => p)
        .map(([s, p]) => `<div><i style="background:${s.color}"></i>${esc(seriesName(s))} <b>${esc(formatValue(hass, s, p[1]))}</b></div>`);
      if (!rows.length) return hide();
      cursor.setAttribute('x1', px);
      cursor.setAttribute('x2', px);
      cursor.setAttribute('visibility', 'visible');
      tip.innerHTML = `<div class="time">${esc(formatTime(hass, ms, { weekday: hours > 24 }))}</div>${rows.join('')}`;
      tip.hidden = false;
      const tw = tip.offsetWidth;
      tip.style.left = `${Math.min(Math.max(0, px + 12 + tw > width ? px - tw - 12 : px + 12), Math.max(0, width - tw))}px`;
      tip.style.top = '4px';
    };
    const hide = () => {
      cursor.setAttribute('visibility', 'hidden');
      tip.hidden = true;
    };
    svg.addEventListener('pointermove', show);
    svg.addEventListener('pointerdown', show);
    svg.addEventListener('pointerleave', hide);
  }
}

// --- Editor --------------------------------------------------------------------------

class KnxMonitorChartCardEditor extends HTMLElement {
  setConfig(config) {
    this._config = { ...config };
    this._render();
  }

  set hass(hass) {
    const first = !this._hass;
    this._hass = hass;
    if (first) this._loadCharts();
    if (this._form) this._form.hass = hass;
  }

  async _loadCharts() {
    try {
      const list = await api(this._hass, '/api/charts');
      this._charts = list.charts.map((c) => c.name);
    } catch (e) {
      this._charts = [];
      this._error = e;
    }
    this._render();
  }

  _render() {
    if (!this._config || !this._hass) return;
    const t = text(this._hass);
    if (!this._form) {
      this._form = document.createElement('ha-form');
      this._form.computeLabel = (s) => t[s.name];
      this._form.addEventListener('value-changed', (e) => {
        const value = { ...e.detail.value };
        const config = { ...this._config, ...value, hours: Number(value.hours) || 24 };
        if (!config.title) delete config.title;
        this._config = config;
        this.dispatchEvent(new CustomEvent('config-changed', { detail: { config }, bubbles: true, composed: true }));
      });
      this._note = document.createElement('div');
      this._note.style.cssText = 'color: var(--secondary-text-color); font-size: 14px; margin-top: 8px;';
      this.append(this._form, this._note);
    }
    const charts = [...(this._charts ?? [])];
    if (this._config.chart && !charts.includes(this._config.chart)) charts.unshift(this._config.chart);
    this._form.hass = this._hass;
    this._form.schema = [
      { name: 'chart', selector: { select: { mode: 'dropdown', options: charts.map((c) => ({ value: c, label: c })) } } },
      {
        name: 'hours',
        selector: { select: { mode: 'list', options: RANGES.map((h) => ({ value: String(h), label: t.range[h] })) } },
      },
      { name: 'title', selector: { text: {} } },
    ];
    this._form.data = { ...this._config, hours: String(this._config.hours ?? 24) };
    this._note.textContent = this._error
      ? t.error(this._error.detail || this._error.kind)
      : this._charts && !this._charts.length
        ? t.noCharts
        : '';
  }
}

if (!customElements.get(CARD)) {
  customElements.define(CARD, KnxMonitorChartCard);
  customElements.define(`${CARD}-editor`, KnxMonitorChartCardEditor);
  const t = String(navigator.language).startsWith('de') ? TEXT.de : TEXT.en;
  window.customCards = window.customCards || [];
  window.customCards.push({
    type: CARD,
    name: t.name,
    description: t.description,
    preview: false,
    documentationURL: 'https://busclear.de',
  });
  console.info(`%c Busclear %c chart card ${VERSION} `, 'background:#437F18;color:#fff', '');
}
