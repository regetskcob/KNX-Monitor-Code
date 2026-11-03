// Telegrams on the drawn distribution board (_partials/verteiler.html): a dot
// of light runs from a push button in the building along the bus cable into
// an actuator (its channel LED follows, the kitchen light with channel 3),
// and the actuator answers with its status, which leaves the cabinet and
// runs down the thread through the page. Where the window has room, the
// sending devices sit on the thread and their keys switch the board for
// real. The live list over the board names every telegram like the monitor,
// its bars count the telegrams per second of the last minute.
// With reduced motion nothing moves; the keys still switch. The setting is
// followed live: switched on, the script stops; switched off, it starts again.
(() => {
  const svg = document.querySelector('.knx-board');
  const data = document.getElementById('tz-telegrams');
  if (!svg || !data) return;
  const script = JSON.parse(data.textContent);
  const words = JSON.parse(document.getElementById('tz-words')?.textContent || '{"on":"On","off":"Off"}');
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  let still = motion.matches;
  const ticker = document.querySelector('.tz-ticker-line');
  const pulse = svg.querySelector('.knx-board-pulse');
  const devices = [...svg.querySelectorAll('.knx-board-device')];
  const ip = svg.querySelector('[data-id="ip"] .dv-led--traffic');
  const trunk = Number(svg.dataset.trunk);
  const exit = Number(svg.dataset.exit);
  const terminal = 131; // bottom of the bus terminal drop (device top 44 + 87)
  const ground = 220;
  const feld = document.querySelector('.tz-feld');
  const thread = document.querySelector('.tz-thread');
  const line = thread?.querySelector('.tz-thread-line');
  const load = thread?.querySelector('.tz-load-line');
  const lamp = thread?.querySelector('.tz-lamp');
  const dot = thread?.querySelector('.tz-thread-pulse');
  const sensors = [...document.querySelectorAll('.tz-sensor')];
  const keys = [...document.querySelectorAll('.tz-key')];

  // Channel LEDs, the keys that show them, and the kitchen light.
  const led = (t) => devices[t.device]?.querySelector(`.dv-led[data-channel="${t.channel}"]`);
  const isOn = (device, channel) => !!led({ device, channel })?.classList.contains('is-on');
  const apply = (t) => {
    if (t.channel === undefined || t.on === undefined) return;
    const l = led(t);
    if (!l) return;
    l.classList.toggle('is-on', t.on);
    // Dimmers: brightness after the value, like the LEDs in the app.
    const pct = parseFloat(t.value);
    l.style.fillOpacity = t.on && !Number.isNaN(pct) ? String(0.35 + 0.65 * pct / 100) : '';
    for (const k of keys) {
      const a = JSON.parse(k.dataset.key);
      if (a.device === t.device && a.channel === t.channel && !a.value) k.querySelector('.tz-key-led').classList.toggle('is-on', t.on);
    }
    if (t.device === 2 && t.channel === 2) lamp?.classList.toggle('is-on', t.on);
  };

  // The live list and its bars: one bar per second, as high as the
  // telegrams in it (up to three).
  const rows = document.querySelector('.tz-rows');
  const bars = document.querySelector('.tz-bars');
  const seen = [];
  const pad = (n, w = 2) => String(n).padStart(w, '0');
  const clock = (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}.${pad(d.getMilliseconds(), 3)}`;
  const list = (t, at = Date.now()) => {
    seen.push(at);
    if (!rows) return;
    const li = document.createElement('li');
    for (const v of [clock(new Date(at)), t.from, t.to, t.text, t.value]) {
      const span = document.createElement('span');
      span.textContent = v;
      li.append(span);
    }
    rows.append(li);
    while (rows.children.length > 8) rows.firstElementChild.remove();
  };
  const drawBars = () => {
    if (!bars) return;
    const now = Date.now();
    while (seen.length && now - seen[0] > 60000) seen.shift();
    const perSecond = new Map();
    for (const at of seen) {
      const s = Math.floor((now - at) / 1000);
      perSecond.set(s, (perSecond.get(s) || 0) + 1);
    }
    bars.replaceChildren(...[...perSecond].map(([s, n]) => {
      const b = document.createElement('i');
      b.className = 'tz-bar';
      b.style.left = `${100 - (s + 0.5) / 0.6}%`;
      b.style.height = `${Math.min(n, 3) / 3 * 100}%`;
      return b;
    }));
  };
  // Windows beside a push button: the blind follows the position status.
  const windows = [...document.querySelectorAll('.tz-window')];
  const blind = (t) => {
    const pct = parseFloat(t.value);
    if (Number.isNaN(pct)) return;
    for (const w of windows) {
      if (w.dataset.status !== t.to) continue;
      w.style.setProperty('--pos', String(pct));
      w.querySelector('.tz-window-label b').textContent = t.value;
    }
  };
  const say = (t) => {
    list(t);
    blind(t);
    drawBars();
    if (!ticker) return;
    ticker.textContent = `${t.from} → ${t.to}   ${t.text}   ${t.value}`;
    ticker.classList.add('is-new');
    requestAnimationFrame(() => requestAnimationFrame(() => ticker.classList.remove('is-new')));
  };

  // A lived-in board to start with: some lights on, and the last half
  // minute in the list (pairs of command and status, irregular gaps).
  for (const [device, channel] of [[2, 1], [2, 5], [2, 6], [4, 2]]) {
    apply({ device, channel, on: true, value: device === 4 ? '40 %' : '' });
  }
  const past = [];
  let back = 0;
  for (let i = script.length - 1; i >= script.length - 10; i--) {
    back += script[i].out ? 120 + Math.random() * 200 : 1500 + Math.random() * 4500;
    past.unshift([script[i], Date.now() - back]);
  }
  for (const [t, at] of past) list(t, at);
  drawBars();

  // Geometry in the coordinates of .tz-feld: points of the board's SVG,
  // the thread, the stubs of the sensors, the load cable to the lamp.
  let geo = null;
  const boardPoint = (x, y) => {
    const o = feld.getBoundingClientRect();
    const p = svg.createSVGPoint();
    p.x = x;
    p.y = y;
    const q = p.matrixTransform(svg.getScreenCTM());
    return [q.x - o.left, q.y - o.top];
  };
  const rounded = (pts, r = 14) => {
    const toward = (v, w, k) => [v[0] + Math.sign(w[0] - v[0]) * k, v[1] + Math.sign(w[1] - v[1]) * k];
    let d = `M${pts[0][0]} ${pts[0][1]}`;
    for (let i = 1; i < pts.length - 1; i++) {
      const [a, b, c] = [pts[i - 1], pts[i], pts[i + 1]];
      const s = toward(b, a, Math.min(r, Math.hypot(b[0] - a[0], b[1] - a[1]) / 2));
      const e = toward(b, c, Math.min(r, Math.hypot(c[0] - b[0], c[1] - b[1]) / 2));
      d += ` L${s[0]} ${s[1]} Q${b[0]} ${b[1]} ${e[0]} ${e[1]}`;
    }
    return `${d} L${pts.at(-1)[0]} ${pts.at(-1)[1]}`;
  };
  const rect = (el) => {
    const o = feld.getBoundingClientRect();
    const r = el.getBoundingClientRect();
    return { left: r.left - o.left, top: r.top - o.top, right: r.right - o.left, bottom: r.bottom - o.top, width: r.width, height: r.height };
  };
  const layout = () => {
    if (!thread || !feld) return;
    const more = document.querySelector('.tz-more');
    // The cable ends above the FAQ, which spans both columns.
    const sections = [...document.querySelectorAll('.hz-feld-section:not(.tz-section--faq)')];
    const facts = sections[0]?.querySelector('.hz-facts');
    for (const s of sensors) s.hidden = true;
    lamp?.classList.remove('is-placed');
    load?.setAttribute('d', '');
    geo = null;
    if (!more || !facts) {
      thread.style.display = 'none';
      return;
    }
    thread.style.display = '';
    // Measure without the SVG itself; it gets the height of what it draws.
    thread.setAttribute('height', '0');
    const fit = (bottom) => thread.setAttribute('height', String(Math.ceil(bottom + 8)));
    const [x0, y0] = boardPoint(exit, ground);
    // The horizon leaves a gap where the cable crosses it.
    const horizon = document.querySelector('.tz-screen .hz-feld-horizon');
    horizon?.style.setProperty('--cut', `${x0 - rect(horizon).left}px`);
    // Phones: the cable straight down, faint behind the text, no devices.
    const narrow = innerWidth <= 760;
    thread.classList.toggle('is-faint', narrow);
    if (narrow) {
      // Right below the horizon the cable turns into the page's margin and
      // runs down there, beside the text; no devices on phones.
      // In the middle of the 16 px margin, off the edge of the display.
      const edge = rect(feld).width - 9;
      const yH = y0 + 14;
      // Down to the end of the page.
      const pts = [[x0, y0], [x0, yH], [edge, yH], [edge, rect(feld).height]];
      line.setAttribute('d', rounded(pts, 8));
      geo = { pts, stubs: new Map() };
      fit(pts.at(-1)[1]);
      return;
    }
    const m = rect(more);
    const f = rect(facts);
    const yA = m.top - 32;
    const xL = m.left - 40;
    const yB = m.bottom + 24;
    const xG = f.left - 16;
    const yE = rect(sections.at(-1)).bottom;
    // The way down ends a curve's length above the split (below).
    const pts = [[x0, y0], [x0, yA], [xL, yA], [xL, yB], [xG, yB], [xG, yE - 14]];
    line.setAttribute('d', rounded(pts));
    geo = { pts, stubs: new Map() };

    // Sensors: above the thread's way left, right of its way down (beside
    // the page), in the first section under its words; each only if it fits.
    const stubs = [];
    for (const s of sensors) {
      s.hidden = false;
      const w = s.offsetWidth;
      const h = s.offsetHeight;
      let at = null;
      let stub = null;
      let seg = 0;
      const slots = s.dataset.slot.split(' ');
      // In the empty space under a section's facts, right of the thread.
      const gap = slots.includes('gap') && document.getElementById(s.dataset.section);
      if (gap) {
        // The list stretches to the row; its last entry is where it ends.
        const fl = rect(gap.querySelector('.hz-facts > :last-child'));
        const sec = rect(gap);
        const left = xG + 48;
        const top = fl.bottom + 32;
        if (sec.bottom - 24 - top > h && sec.right - 16 - left > w) {
          at = [left, top];
          // Into the middle of the button, not of button and window.
          const body = s.querySelector('.tz-sensor-body');
          const cy = top + body.offsetTop + body.offsetHeight / 2;
          stub = [[left, cy], [xG, cy]];
          seg = 4;
        }
      }
      if (!at && slots.includes('top') && yA - y0 > h + 72) {
        const cx = xL + (x0 - xL) * 0.42;
        at = [cx - w / 2, yA - 36 - h];
        stub = [[cx, yA - 36], [cx, yA]];
        seg = 1;
      } else if (!at && slots.includes('right') && x0 + 72 + w < innerWidth - 24 - feld.getBoundingClientRect().left && yA - y0 > h + 40) {
        const cy = y0 + (yA - y0) / 2;
        at = [x0 + 72, cy - h / 2];
        stub = [[x0 + 72, cy + 8], [x0, cy + 8]];
        seg = 0;
      } else if (!at && slots.includes('section')) {
        const words = sections[0].querySelector(':scope > div');
        const box = rect(words);
        const sec = rect(sections[0]);
        const top = box.bottom + 40;
        if (sec.bottom - 24 - top > h && xG - box.left > w + 48) {
          const left = box.left + (xG - box.left - w) / 2;
          at = [left, top];
          const cy = top + h / 2 + 10;
          stub = [[left + w, cy], [xG, cy]];
          seg = 4;
        }
      }
      if (!at) {
        s.hidden = true;
        continue;
      }
      s.style.left = `${at[0]}px`;
      s.style.top = `${at[1]}px`;
      stubs.push(stub);
      geo.stubs.set(s.dataset.addr, { stub, seg });
    }
    // The KNX box on the bus: its network cable (the end of the drawing,
    // 380/240 in its viewBox) down a little and across to the thread.
    const extra = [];
    const pi = document.querySelector('.tz-pi');
    if (pi) {
      const r = rect(pi);
      const k = r.width / 400;
      const [ex, ey] = [r.left + 380 * k, r.top + 240 * k];
      if (xG - ex > 24) extra.push(rounded([[ex, ey - 2], [ex, ey + 14], [xG, ey + 14]], 8));
    }
    // The end: above the FAQ the cable splits, left out to the window's
    // edge, right along the section's border and down to the end of the page.
    const end = rect(feld).height;
    const xR = rect(sections.at(-1)).right - 24;
    extra.push(
      rounded([[xG, yE - 14], [xG, yE], [-feld.getBoundingClientRect().left, yE]]),
      rounded([[xG, yE - 14], [xG, yE], [xR, yE], [xR, end]]),
    );
    // The stubs belong to the thread's path; one path keeps them in one stroke.
    line.setAttribute('d', [rounded(pts), ...stubs.map((p) => `M${p[0][0]} ${p[0][1]} L${p[1][0]} ${p[1][1]}`), ...extra].join(' '));

    // The lamp in the open space above the words, on a load cable from the
    // top terminal of switch actuator channel 3, out of the cabinet's top.
    const stage = document.querySelector('.tz-hero');
    const wordsCol = document.querySelector('.tz-words');
    const live = document.querySelector('.tz-live');
    const aside = live && getComputedStyle(live).display !== 'none' ? live : svg;
    const hero = rect(stage);
    const wordsRight = Math.max(...[...wordsCol.children].map((c) => rect(c).right));
    const gapX = (wordsRight + rect(aside).left) / 2;
    const room = hero.top - 24;
    if (lamp && room > 120 && rect(aside).left - wordsRight > 28) {
      const dev = devices[2];
      const cx = Number(dev.dataset.x) + Number(dev.dataset.x0) + 2.5 * 10 + 2.4;
      const [tx, ty] = boardPoint(cx, 44 + 7.7);
      const [, cabTop] = boardPoint(cx, 14);
      const ly = Math.max(56, room / 2);
      lamp.setAttribute('transform', `translate(${gapX} ${ly})`);
      lamp.classList.add('is-placed');
      load.setAttribute('d', rounded([[tx, ty], [tx, cabTop - 18], [gapX, cabTop - 18], [gapX, ly + 24]], 10));
    }
    fit(end);
  };
  layout();
  addEventListener('resize', layout);
  addEventListener('load', layout);
  document.fonts?.ready.then(layout);
  // Content that changes height later (the iPad's picture, fonts) moves the
  // thread's way; follow it once per frame.
  let pending = 0;
  const main = document.querySelector('.tz-main');
  if (main && 'ResizeObserver' in window) {
    new ResizeObserver(() => {
      cancelAnimationFrame(pending);
      pending = requestAnimationFrame(layout);
    }).observe(main);
  }

  // Moving dots: along a polyline in .tz-feld (thread, stubs) and along the
  // board's cable (its own SVG units).
  const along = (points, speed, el, done, min = 300) => {
    const seg = points.slice(1).map((p, i) => Math.hypot(p[0] - points[i][0], p[1] - points[i][1]));
    const total = seg.reduce((a, b) => a + b, 0);
    const ms = Math.max(min, total * speed);
    const start = performance.now();
    el.classList.add('is-running');
    const step = (now) => {
      const k = Math.min(1, (now - start) / ms);
      let d = k * total;
      let i = 0;
      while (i < seg.length - 1 && d > seg[i]) d -= seg[i++];
      const f = seg[i] ? d / seg[i] : 1;
      const [ax, ay] = points[i];
      const [bx, by] = points[i + 1];
      el.setAttribute('cx', ax + (bx - ax) * f);
      el.setAttribute('cy', ay + (by - ay) * f);
      if (el.ownerSVGElement === svg && ip) ip.classList.toggle('is-on', Math.abs(ax + (bx - ax) * f - Number(devices[1].dataset.bus)) < 14 && ay === trunk);
      if (k < 1) requestAnimationFrame(step);
      else { el.classList.remove('is-running'); done(); }
    };
    requestAnimationFrame(step);
  };
  const threadDot = () => {
    const node = dot.cloneNode();
    thread.append(node);
    return node;
  };
  // From a sensor along its stub and up the thread to the cabinet.
  const upFrom = (addr, done, fast) => {
    const s = geo?.stubs.get(addr);
    if (!s) return done();
    const pts = [...s.stub, ...geo.pts.slice(0, s.seg + 1).reverse()];
    const node = threadDot();
    along(pts, fast ? 0.18 : 0.9, node, () => { node.remove(); done(); }, fast ? 120 : 300);
  };
  // A status down the whole thread.
  const down = () => {
    if (!geo) return;
    const node = threadDot();
    along(geo.pts, 1.4, node, () => node.remove());
  };
  const board = (t, done, fast) => {
    const x = Number(devices[t.device].dataset.bus);
    const inward = [[exit, ground], [exit, trunk], [x, trunk], [x, terminal]];
    // Each telegram its own dot, so a key press never waits for the script.
    const node = pulse.cloneNode();
    svg.append(node);
    along(t.out ? inward.reverse() : inward, fast ? 0.7 : t.out ? 2.4 : 3.2, node, () => { node.remove(); done(); }, fast ? 120 : 300);
  };
  const flash = (addr, key) => {
    const s = sensors.find((e) => e.dataset.addr === addr && !e.hidden);
    const l = key?.querySelector('.tz-key-led') || s?.querySelector('.tz-presence-led, .tz-key-led');
    if (!l) return;
    l.classList.add('is-sending');
    setTimeout(() => l.classList.remove('is-sending'), 500);
  };

  // The script sends one telegram at a time; key presses go out at once.
  const queue = [];
  // Channels a visitor switched; the script leaves them alone for a while.
  const touched = new Map();
  const leaveAlone = (t) => t.channel !== undefined && Date.now() - (touched.get(`${t.device}/${t.channel}`) || 0) < 30000;
  let busy = false;
  const send = (t, key) => {
    say(t);
    if (still) {
      apply(t);
      return Promise.resolve();
    }
    return new Promise((resolve) => {
      if (t.out) {
        if (t.on !== undefined) apply(t);
        board(t, () => { down(); resolve(); });
      } else {
        flash(t.from, key);
        // A key press answers at once (about 0.4 s); the script takes its time.
        const fast = !!key;
        upFrom(t.from, () => board(t, () => { apply(t); resolve(); }, fast), fast);
      }
    });
  };
  const pump = async () => {
    if (busy) return;
    busy = true;
    while (queue.length) {
      const [t, key, wait] = queue.shift();
      await send(t, key);
      await new Promise((r) => setTimeout(r, wait));
    }
    busy = false;
  };

  for (const k of keys) {
    k.addEventListener('click', () => {
      const a = JSON.parse(k.dataset.key);
      const addr = k.closest('.tz-sensor').dataset.addr;
      const on = a.value ? true : !isOn(a.device, a.channel);
      const value = a.value || (on ? words.on : words.off);
      const command = { from: addr, to: a.to, text: a.text, value, device: a.device, channel: a.channel, on };
      const status = { from: devices[a.device].querySelector('.knx-board-addr').textContent, to: a.status, text: a.status_text,
        value: a.status_value || value, device: a.device, out: true, ...(a.value ? { channel: a.channel, on: false } : {}) };
      touched.set(`${a.device}/${a.channel}`, Date.now());
      k.classList.add('is-pressed');
      setTimeout(() => k.classList.remove('is-pressed'), 180);
      // At once, beside whatever the script is sending.
      send(command, k).then(() => new Promise((r) => setTimeout(r, 120))).then(() => send(status));
    });
  }

  // The script: irregular like a real line. A status follows its command at
  // once, then a pause of a moment up to several seconds, now and then a
  // quick burst.
  let n = 0;
  // Each start a new run; a run left over from before ends by itself.
  let run = 0;
  const auto = (r) => {
    if (still || r !== run) return;
    if (queue.length || busy) {
      setTimeout(() => auto(r), 800);
      return;
    }
    let t = script[n++ % script.length];
    // Skip a command (and its status) on a channel the visitor just used.
    while (!t.out && leaveAlone(t)) {
      if (script[n % script.length].out) n++;
      t = script[n++ % script.length];
    }
    const following = script[n % script.length];
    const wait = following.out ? 150 : Math.random() < 0.25 ? 300 : 900 + Math.random() * 4200;
    queue.push([t, null, 0]);
    pump().then(() => setTimeout(() => auto(r), wait));
  };
  // Still: one telegram in the list and no script; moving: the script.
  const start = () => {
    const r = ++run;
    queue.length = 0;
    if (still) say(script[n % script.length]);
    else setTimeout(() => auto(r), 700);
  };
  motion.addEventListener('change', (e) => {
    still = e.matches;
    start();
  });
  setInterval(drawBars, 1000);
  start();
})();
