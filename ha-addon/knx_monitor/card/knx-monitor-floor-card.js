// Busclear – dashboard card "Busclear Grundriss" (custom:knx-monitor-floor-card).
//
// Shows the bus on a floor plan: points light up when one of their group
// addresses is on the bus, silent ones stand out. The plan is the bus view
// saved in the app ("Bus auf dem Grundriss", floor_view.json). The add-on
// puts this file into /config/www/knx-monitor/ on every start and fills in the
// placeholders (server/lib/src/lovelace_card.dart); the data comes via Ingress
// from the add-on (/api/floor-view, read-only).
//
// A technical view, not a control panel: nothing here sends to the bus.
//
// No build step and no dependencies. Names from the plan are data from a file:
// the card builds every element with createElement and textContent and never
// puts them into markup.

const INGRESS = '__KNX_MONITOR_INGRESS__';
const VERSION = '__KNX_MONITOR_VERSION__';
const CARD = 'knx-monitor-floor-card';

/** Reload while the card is visible. */
const REFRESH_MS = 5 * 1000;

/** A point counts as active this long after its last telegram. */
const ACTIVE_MS = 12 * 1000;

/** Silence only stands out once the bus has been known this long (as the watcher "stopped sending"). */
const SILENT_AFTER_MS = 12 * 3600 * 1000;

const SVG_NS = 'http://www.w3.org/2000/svg';
const WIDTH = 1000;

const TEXT = {
  de: {
    name: 'Busclear Grundriss',
    description: 'Der Bus auf deinem Grundriss: Telegramme lassen Punkte aufleuchten, stumme fallen auf.',
    floor: 'Ebene',
    title: 'Titel (optional)',
    loading: 'Lade …',
    none: 'Noch keine Busansicht. Lege sie in Busclear unter „Bus auf dem Grundriss“ an.',
    noFloor: 'Diese Ebene gibt es in der Busansicht nicht mehr.',
    error: (d) => `Busclear nicht erreichbar (${d}).`,
    active: 'gerade aktiv',
    heard: 'gehört',
    unheard: 'noch nichts gehört',
    silent: 'lange still',
    unlinked: 'ohne Adresse',
    silentList: 'Lange still',
    since: (d) => `beobachtet seit ${d}`,
    last: (d) => `zuletzt ${d}`,
    history: 'Verlauf wird gelesen …',
    plan: 'Grundriss',
  },
  en: {
    name: 'Busclear floor plan',
    description: 'The bus on your floor plan: telegrams light up points, silent ones stand out.',
    floor: 'Level',
    title: 'Title (optional)',
    loading: 'Loading …',
    none: 'No bus view yet. Create it in Busclear under “Bus on the floor plan”.',
    noFloor: 'This level no longer exists in the bus view.',
    error: (d) => `Busclear not reachable (${d}).`,
    active: 'active now',
    heard: 'heard',
    unheard: 'not heard yet',
    silent: 'silent for long',
    unlinked: 'no address',
    silentList: 'Silent for long',
    since: (d) => `watched since ${d}`,
    last: (d) => `last ${d}`,
    history: 'Reading the history …',
    plan: 'Floor plan',
  },
};

const text = (hass) => (String(hass?.locale?.language ?? hass?.language ?? 'en').startsWith('de') ? TEXT.de : TEXT.en);

// --- DOM helpers: text only ever through textContent --------------------------------

function el(tag, className, content) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (content != null) node.textContent = String(content);
  return node;
}

function svg(tag, attrs, content) {
  const node = document.createElementNS(SVG_NS, tag);
  for (const [k, v] of Object.entries(attrs ?? {})) node.setAttribute(k, String(v));
  if (content != null) node.textContent = String(content);
  return node;
}

/** A finite number within [min, max], otherwise [fallback]. The answer is data, not trusted. */
function num(v, min, max, fallback) {
  return typeof v === 'number' && Number.isFinite(v) ? Math.min(max, Math.max(min, v)) : fallback;
}

const str = (v) => (typeof v === 'string' ? v.slice(0, 80) : '');

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
  const ready = hass.callWS({ type: 'supervisor/api', endpoint: '/ingress/session', method: 'post' }).then((r) => {
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
    if (!retry && (res.status === 401 || res.status === 403)) continue;
    throw new ApiError('http', `HTTP ${res.status}`);
  }
  throw new ApiError('http');
}

// --- State of a point ----------------------------------------------------------------

/**
 * 'active' | 'heard' | 'unheard' | 'silent' | 'unlinked' and the time of the last telegram.
 * Nothing heard is neutral ('unheard') until the bus has been known for SILENT_AFTER_MS.
 */
function stateOf(point, last, now, since) {
  const addresses = Array.isArray(point.addresses) ? point.addresses : [];
  if (!addresses.length) return { state: 'unlinked', at: null };
  let at = null;
  for (const a of addresses) {
    const t = last?.[String(a)];
    if (typeof t === 'number' && (at == null || t > at)) at = t;
  }
  if (at == null) {
    const watched = typeof since === 'number' ? now - since : 0;
    return { state: watched >= SILENT_AFTER_MS ? 'silent' : 'unheard', at: null };
  }
  return { state: now - at <= ACTIVE_MS ? 'active' : 'heard', at };
}

function formatWhen(hass, ms) {
  const sameDay = Date.now() - ms < 20 * 3600 * 1000;
  const options = sameDay
    ? { hour: '2-digit', minute: '2-digit' }
    : { weekday: 'short', day: 'numeric', month: 'numeric', hour: '2-digit', minute: '2-digit' };
  return new Intl.DateTimeFormat(hass?.locale?.language ?? undefined, options).format(new Date(ms));
}

// --- Card ----------------------------------------------------------------------------

const STYLE = `
  :host { display: block; }
  ha-card { padding: 12px 16px 12px; overflow: hidden; }
  .head { display: flex; align-items: center; gap: 8px; min-height: 28px; }
  .title { flex: 1; font-size: 16px; font-weight: 500; color: var(--primary-text-color);
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .floors { display: flex; gap: 2px; flex-wrap: wrap; }
  .floors button { font: inherit; font-size: 12px; padding: 2px 8px; border-radius: 6px; cursor: pointer;
    border: 1px solid transparent; background: none; color: var(--secondary-text-color); min-height: 44px;
    min-width: 44px; }
  .floors button[aria-pressed="true"] { border-color: var(--divider-color); color: var(--primary-text-color); }
  .plan { position: relative; margin-top: 8px; border: 1px solid var(--divider-color); border-radius: 8px;
    overflow: hidden; background: var(--secondary-background-color, transparent); }
  svg { display: block; width: 100%; height: auto; }
  svg text { font-size: 26px; fill: var(--secondary-text-color); }
  .room { fill: none; stroke: var(--secondary-text-color); stroke-width: 3; }
  .point { cursor: pointer; }
  .point:focus { outline: none; }
  .point:focus .focus, .point.selected .focus { stroke: var(--primary-text-color); }
  .focus { fill: transparent; stroke: transparent; stroke-width: 3; }
  .active .halo { fill: var(--primary-color); fill-opacity: .2; stroke: var(--primary-color); stroke-width: 4; }
  .active .dot { fill: var(--primary-color); }
  .heard .dot { fill: var(--secondary-text-color); stroke: var(--card-background-color, #fff); stroke-width: 4; }
  .unheard .dot { fill: var(--card-background-color, #fff); stroke: var(--secondary-text-color); stroke-width: 4; }
  .silent .dot { fill: var(--card-background-color, #fff); stroke: var(--warning-color, #b18334); stroke-width: 5; }
  .silent text { fill: var(--warning-color, #b18334); font-weight: 700; font-size: 28px; }
  .unlinked .dot { fill: var(--card-background-color, #fff); stroke: var(--secondary-text-color); stroke-width: 3; }
  .legend { display: flex; flex-wrap: wrap; gap: 4px 14px; margin: 8px 0 0; font-size: 12px;
    color: var(--secondary-text-color); }
  .detail, .quiet { font-size: 13px; margin-top: 6px; color: var(--primary-text-color); }
  .quiet b { font-weight: 500; }
  .muted { color: var(--secondary-text-color); }
  .note { color: var(--secondary-text-color); font-size: 14px; padding: 16px 0 8px; }
`;

class KnxMonitorFloorCard extends HTMLElement {
  static getStubConfig() {
    return { floor: '' };
  }

  static getConfigElement() {
    return document.createElement(`${CARD}-editor`);
  }

  constructor() {
    super();
    this.attachShadow({ mode: 'open' });
    this._data = null;
    this._error = null;
    this._selected = null;
    this._timer = null;
    this._loading = false;
  }

  setConfig(config) {
    this._config = { floor: '', title: '', ...(config ?? {}) };
    this._floor = str(this._config.floor);
    this._render();
  }

  set hass(hass) {
    const first = !this._hass;
    this._hass = hass;
    if (first) this._load();
  }

  getCardSize() {
    return 6;
  }

  connectedCallback() {
    this._timer = setInterval(() => {
      if (!document.hidden) this._load();
    }, REFRESH_MS);
    this._load();
  }

  disconnectedCallback() {
    clearInterval(this._timer);
    this._timer = null;
  }

  async _load() {
    if (!this._hass || this._loading) return;
    this._loading = true;
    try {
      const data = await api(this._hass, '/api/floor-view');
      this._data = data && typeof data === 'object' ? data : null;
      this._error = null;
    } catch (e) {
      this._error = e;
    } finally {
      this._loading = false;
    }
    this._render();
  }

  _render() {
    const root = this.shadowRoot;
    if (!root || !this._config) return;
    const t = text(this._hass);
    const style = document.createElement('style');
    style.textContent = STYLE;
    const card = document.createElement('ha-card');
    const head = el('div', 'head');
    head.append(el('div', 'title', str(this._config.title) || t.name));
    card.append(head);
    const note = (message) => card.append(el('div', 'note', message));

    const data = this._data;
    const floors = Array.isArray(data?.floors) ? data.floors.filter((f) => f && typeof f === 'object') : [];
    if (this._error && !data) {
      note(t.error(this._error.detail || this._error.kind || ''));
    } else if (!data) {
      note(t.loading);
    } else if (data.available !== true || !floors.length) {
      note(t.none);
    } else {
      const floor = floors.find((f) => f.id === this._floor) ?? (this._config.floor ? null : floors[0]);
      if (floors.length > 1) {
        const bar = el('div', 'floors');
        for (const f of floors) {
          const b = el('button', '', str(f.name) || str(f.id));
          b.type = 'button';
          b.setAttribute('aria-pressed', String(f === floor));
          b.addEventListener('click', () => {
            this._floor = str(f.id);
            this._selected = null;
            this._render();
          });
          bar.append(b);
        }
        head.append(bar);
      }
      if (!floor) note(t.noFloor);
      else this._renderFloor(card, floor, data, t);
    }
    root.replaceChildren(style, card);
  }

  _renderFloor(card, floor, data, t) {
    const now = num(data.now, 0, Number.MAX_SAFE_INTEGER, Date.now());
    const aspect = num(floor.aspect, 0.2, 5, 1.5);
    const height = Math.round(WIDTH / aspect);
    const view = svg('svg', { viewBox: `0 0 ${WIDTH} ${height}`, role: 'group', 'aria-label': t.plan });
    if (floor.image === true && !INGRESS.startsWith('__')) {
      view.append(
        svg('image', {
          href: `${INGRESS}/api/floor-view/image?floor=${encodeURIComponent(str(floor.id))}`,
          x: 0,
          y: 0,
          width: WIDTH,
          height,
          preserveAspectRatio: 'none',
        }),
      );
    }
    for (const r of Array.isArray(floor.rooms) ? floor.rooms : []) {
      if (!r || typeof r !== 'object') continue;
      const x = num(r.x, 0, 1, 0) * WIDTH;
      const y = num(r.y, 0, 1, 0) * height;
      view.append(
        svg('rect', { class: 'room', x, y, width: num(r.w, 0, 1, 0.2) * WIDTH, height: num(r.h, 0, 1, 0.2) * height }),
      );
      if (floor.image !== true && str(r.name)) view.append(svg('text', { x: x + 12, y: y + 34 }, str(r.name)));
    }
    const points = (Array.isArray(floor.points) ? floor.points : []).filter((p) => p && typeof p === 'object');
    const silent = [];
    let selected = null;
    for (const p of points) {
      const { state, at } = stateOf(p, data.last, now, data.since);
      const name = str(p.name) || str(p.id);
      if (state === 'silent') silent.push(name);
      const label = [name, str(p.room), t[state]].filter(Boolean).join(', ');
      const isSelected = this._selected != null && this._selected === p.id;
      if (isSelected) selected = { name, room: str(p.room), state, at };
      const g = svg('g', {
        class: `point ${state}${isSelected ? ' selected' : ''}`,
        transform: `translate(${num(p.x, 0, 1, 0.5) * WIDTH} ${num(p.y, 0, 1, 0.5) * height})`,
        tabindex: 0,
        role: 'button',
        'aria-label': label,
      });
      g.append(svg('title', null, label), svg('circle', { class: 'focus', r: 30 }));
      // A shape per state, so it does not depend on colour: ring with dot, dot, hollow ring, ring
      // with mark, square.
      if (state === 'active') g.append(svg('circle', { class: 'halo', r: 24 }), svg('circle', { class: 'dot', r: 10 }));
      else if (state === 'heard') g.append(svg('circle', { class: 'dot', r: 11 }));
      else if (state === 'unheard') g.append(svg('circle', { class: 'dot', r: 11 }));
      else if (state === 'silent') {
        g.append(svg('circle', { class: 'dot', r: 17 }), svg('text', { 'text-anchor': 'middle', y: 10 }, '!'));
      } else g.append(svg('rect', { class: 'dot', x: -9, y: -9, width: 18, height: 18 }));
      const pick = () => {
        this._selected = p.id;
        this._render();
      };
      g.addEventListener('click', pick);
      g.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          pick();
        }
      });
      view.append(g);
    }
    const plan = el('div', 'plan');
    plan.append(view);
    card.append(plan);

    const legend = el('div', 'legend');
    for (const [mark, key] of [['◉', 'active'], ['●', 'heard'], ['○', 'unheard'], ['!', 'silent'], ['□', 'unlinked']]) {
      legend.append(el('span', '', `${mark} ${t[key]}`));
    }
    card.append(legend);

    if (selected) {
      const detail = el('div', 'detail');
      detail.append(el('b', '', selected.name));
      const when =
        selected.at != null
          ? t.last(formatWhen(this._hass, selected.at))
          : (selected.state === 'silent' || selected.state === 'unheard') && typeof data.since === 'number'
            ? t.since(formatWhen(this._hass, data.since))
            : '';
      detail.append(el('span', 'muted', ` · ${[selected.room, t[selected.state], when].filter(Boolean).join(' · ')}`));
      card.append(detail);
    }
    if (silent.length) {
      const quiet = el('div', 'quiet');
      quiet.append(el('b', '', `${t.silentList} (${silent.length}): `), el('span', '', silent.slice(0, 12).join(', ')));
      if (silent.length > 12) quiet.append(el('span', 'muted', ' …'));
      if (typeof data.since === 'number') {
        quiet.append(el('span', 'muted', ` · ${t.since(formatWhen(this._hass, data.since))}`));
      }
      card.append(quiet);
    }
    if (data.loading === true) card.append(el('div', 'legend', t.history));
  }
}

// --- Editor --------------------------------------------------------------------------

class KnxMonitorFloorCardEditor extends HTMLElement {
  setConfig(config) {
    this._config = { floor: '', title: '', ...(config ?? {}) };
    this._render();
  }

  set hass(hass) {
    const first = !this._hass;
    this._hass = hass;
    if (!first) return;
    api(hass, '/api/floor-view')
      .then((data) => {
        this._floors = Array.isArray(data?.floors) ? data.floors.filter((f) => f && typeof f === 'object') : [];
        this._render();
      })
      .catch(() => {
        this._floors = [];
        this._render();
      });
  }

  _change(key, value) {
    this._config = { ...this._config, [key]: value };
    this.dispatchEvent(new CustomEvent('config-changed', { detail: { config: this._config }, bubbles: true, composed: true }));
  }

  _render() {
    if (!this._config) return;
    const t = text(this._hass);
    const wrap = el('div');
    wrap.style.cssText = 'display:grid;gap:12px;padding:8px 0';
    const field = (labelText, control) => {
      const label = el('label');
      label.style.cssText = 'display:grid;gap:4px;font-size:14px';
      label.append(el('span', '', labelText), control);
      return label;
    };
    const select = document.createElement('select');
    select.append(new Option('—', ''));
    for (const f of this._floors ?? []) select.append(new Option(str(f.name) || str(f.id), str(f.id)));
    select.value = str(this._config.floor);
    select.addEventListener('change', () => this._change('floor', select.value));
    const title = document.createElement('input');
    title.type = 'text';
    title.maxLength = 80;
    title.value = str(this._config.title);
    title.addEventListener('change', () => this._change('title', title.value));
    wrap.append(field(t.floor, select), field(t.title, title));
    this.replaceChildren(wrap);
  }
}

if (!customElements.get(CARD)) {
  customElements.define(CARD, KnxMonitorFloorCard);
  customElements.define(`${CARD}-editor`, KnxMonitorFloorCardEditor);
  const t = String(navigator.language).startsWith('de') ? TEXT.de : TEXT.en;
  window.customCards = window.customCards || [];
  window.customCards.push({
    type: CARD,
    name: t.name,
    description: t.description,
    preview: false,
    documentationURL: 'https://busclear.de',
  });
  console.info(`%c Busclear %c floor card ${VERSION} `, 'background:#437F18;color:#fff', '');
}
