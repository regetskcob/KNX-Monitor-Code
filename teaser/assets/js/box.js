// The KNX box page (layouts/box.html): the Pi's cable runs on below the
// horizon through the page like the thread of the landing page. Telegrams
// arrive along it as dots of light and the Pi's LED blinks; then a dot runs
// down the cable past the coupled laptop, whose log gets the row as it
// passes, like the app shows the box's recording. Where the window
// has room, the glass push button sits on the cable; its keys send their own
// telegrams to the box. With reduced motion nothing moves, the log still
// follows the keys. The setting is followed live.
(() => {
  const pi = document.querySelector('.tz-hero .tz-pi, .hz-feld-hero .tz-pi');
  const data = document.getElementById('tz-telegrams');
  if (!pi || !data) return;
  const script = JSON.parse(data.textContent);
  const words = JSON.parse(document.getElementById('tz-words')?.textContent || '{"on":"On","off":"Off"}');
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  let still = motion.matches;
  const feld = document.querySelector('.tz-feld');
  const thread = document.querySelector('.tz-thread');
  const line = thread?.querySelector('.tz-thread-line');
  const dot = thread?.querySelector('.tz-thread-pulse');
  const sensor = document.querySelector('.tz-sensor');
  const keys = [...document.querySelectorAll('.tz-key')];
  const led = pi.querySelector('.tz-pi-led');

  // The log on the laptop: the newest row at the bottom, today's count above.
  const rows = document.querySelector('.tz-boxlog-rows');
  const count = document.querySelector('.tz-boxlog-n');
  let total = 12408;
  const pad = (n, w = 2) => String(n).padStart(w, '0');
  const clock = (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}.${pad(d.getMilliseconds(), 3)}`;
  const group = new Intl.NumberFormat(document.documentElement.lang).format;
  // The rows to start with are already in today's count.
  const list = (t, at = Date.now(), mine = false, counted = false) => {
    if (!counted) total++;
    if (count) count.textContent = group(total);
    if (!rows) return;
    const li = document.createElement('li');
    if (mine) li.className = 'is-mine';
    for (const v of [clock(new Date(at)), t.from, t.to, t.text, t.value]) {
      const span = document.createElement('span');
      span.textContent = v;
      li.append(span);
    }
    rows.append(li);
    while (rows.children.length > 16) rows.firstElementChild.remove();
  };
  // The last half minute to start with.
  let back = 0;
  const past = [];
  for (let i = 15; i >= 0; i--) {
    back += script[i % script.length].out ? 120 + Math.random() * 200 : 1500 + Math.random() * 4500;
    past.unshift([script[i % script.length], Date.now() - back]);
  }
  for (const [t, at] of past) list(t, at, false, true);
  const blink = () => {
    led?.classList.add('is-on');
    setTimeout(() => led?.classList.remove('is-on'), 160);
  };

  // Geometry in the coordinates of .tz-feld.
  let geo = null;
  const rect = (el) => {
    const o = feld.getBoundingClientRect();
    const r = el.getBoundingClientRect();
    return { left: r.left - o.left, top: r.top - o.top, right: r.right - o.left, bottom: r.bottom - o.top, width: r.width, height: r.height };
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
  const layout = () => {
    if (!thread || !feld) return;
    const sections = [...document.querySelectorAll('.hz-feld-section:not(.tz-section--faq)')];
    const facts = sections[0]?.querySelector('.hz-facts');
    const horizon = document.querySelector('.hz-feld-hero + .hz-feld-horizon');
    if (sensor) sensor.hidden = true;
    geo = null;
    // Phones: the hero leaves out the Pi, so there is no cable to follow.
    if (!facts || !horizon || !sections.length || !pi.getBoundingClientRect().width) {
      horizon?.style.removeProperty('--cut');
      thread.style.display = 'none';
      return;
    }
    thread.style.display = '';
    thread.setAttribute('height', '0');
    const fit = (bottom) => thread.setAttribute('height', String(Math.ceil(bottom + 8)));
    // The end of the Pi's cable (380/240 in its viewBox).
    const p = rect(pi);
    const k = p.width / 400;
    const x0 = p.left + 380 * k;
    const y0 = p.top + 240 * k;
    // The horizon leaves a gap where the cable crosses it.
    horizon.style.setProperty('--cut', `${x0 - rect(horizon).left}px`);
    const end = rect(feld).height;
    // Phones: the cable straight down in the margin, faint behind the text.
    const narrow = innerWidth <= 760;
    thread.classList.toggle('is-faint', narrow);
    if (narrow) {
      const edge = rect(feld).width - 9;
      const yH = y0 + 14;
      const pts = [[x0, y0], [x0, yH], [edge, yH], [edge, end]];
      line.setAttribute('d', rounded(pts, 8));
      geo = { pts, in: pts.slice(0, 3).reverse() };
      fit(end);
      return;
    }
    // Below the horizon to the left, between the columns down to the FAQ.
    const f = rect(facts);
    const xG = f.left - 16;
    const yA = Math.min(rect(horizon).top + 28, f.top - 20);
    const yE = rect(sections.at(-1)).bottom;
    const pts = [[x0, y0], [x0, yA], [xG, yA], [xG, yE - 14]];
    // Telegrams from the bus come up the last stretch into the Pi.
    geo = { pts, in: [[xG, Math.min(yA + 160, yE - 14)], ...pts.slice(0, 3).reverse()] };
    // Down past the laptop: the middle of its screen.
    const screen = document.querySelector('.tz-boxlog');
    if (screen) {
      const s = rect(screen);
      const y = Math.min(s.top + s.height / 2, yE - 14);
      // How far down the cable the laptop is.
      if (y > yA) geo.log = Math.abs(x0 - xG) + (yA - y0) + (y - yA);
    }

    // The push button under the words of the first section, if it fits.
    let stub = null;
    if (sensor) {
      sensor.hidden = false;
      const w = sensor.offsetWidth;
      const h = sensor.offsetHeight;
      // The words stretch to the row; their last paragraph is where they end.
      const words = sections[0].querySelector(':scope > div');
      const box = rect(words);
      const sec = rect(sections[0]);
      const top = Math.max(...[...words.children].map((c) => rect(c).bottom)) + 40;
      if (sec.bottom - 24 - top > h && xG - box.left > w + 48) {
        const left = box.left + (xG - box.left - w) / 2;
        sensor.style.left = `${left}px`;
        sensor.style.top = `${top}px`;
        const body = sensor.querySelector('.tz-sensor-body');
        const cy = top + body.offsetTop + body.offsetHeight / 2;
        stub = [[left + w, cy], [xG, cy]];
        geo.from = [...stub, ...pts.slice(0, 3).reverse()];
      } else {
        sensor.hidden = true;
      }
    }
    // Above the FAQ the cable splits, left out to the window's edge, right
    // along the section's border and down to the end of the page.
    const xR = rect(sections.at(-1)).right - 24;
    line.setAttribute('d', [
      rounded(pts),
      ...(stub ? [`M${stub[0][0]} ${stub[0][1]} L${stub[1][0]} ${stub[1][1]}`] : []),
      rounded([[xG, yE - 14], [xG, yE], [-feld.getBoundingClientRect().left, yE]]),
      rounded([[xG, yE - 14], [xG, yE], [xR, yE], [xR, end]]),
    ].join(' '));
    fit(end);
  };
  layout();
  addEventListener('resize', layout);
  addEventListener('load', layout);
  document.fonts?.ready.then(layout);
  let pending = 0;
  const main = document.querySelector('.tz-main');
  if (main && 'ResizeObserver' in window) {
    new ResizeObserver(() => {
      cancelAnimationFrame(pending);
      pending = requestAnimationFrame(layout);
    }).observe(main);
  }

  // A dot along a polyline in .tz-feld.
  // `pass` [distance, fn]: called once when the dot has run that far.
  const along = (points, speed, done, min = 300, pass = null) => {
    const seg = points.slice(1).map((q, i) => Math.hypot(q[0] - points[i][0], q[1] - points[i][1]));
    const length = seg.reduce((a, b) => a + b, 0);
    const ms = Math.max(min, length * speed);
    const node = dot.cloneNode();
    thread.append(node);
    node.classList.add('is-running');
    const start = performance.now();
    const step = (now) => {
      const k = Math.min(1, (now - start) / ms);
      let d = k * length;
      if (pass && d >= pass[0]) {
        pass[1]();
        pass = null;
      }
      let i = 0;
      while (i < seg.length - 1 && d > seg[i]) d -= seg[i++];
      const f = seg[i] ? d / seg[i] : 1;
      const [ax, ay] = points[i];
      const [bx, by] = points[i + 1];
      node.setAttribute('cx', ax + (bx - ax) * f);
      node.setAttribute('cy', ay + (by - ay) * f);
      if (k < 1) requestAnimationFrame(step);
      else { node.remove(); done(); }
    };
    requestAnimationFrame(step);
  };
  // On to the laptop one dot at a time: it takes along every row that
  // reached the box meanwhile, and the log gets them as it passes.
  const waiting = [];
  let toLaptop = false;
  const toLog = (t, mine) => {
    waiting.push([t, mine, Date.now()]);
    if (still || !geo?.log) {
      for (const [w, m, at] of waiting.splice(0)) list(w, at, m);
      return;
    }
    if (toLaptop) return;
    toLaptop = true;
    // Down the whole cable like a status on the landing page; the next dot
    // may leave once this one has passed the laptop.
    along(geo.pts, 1.4, () => {}, 300, [geo.log, () => {
      toLaptop = false;
      for (const [w, m, at] of waiting.splice(0)) list(w, at, m);
    }]);
  };
  // A telegram reaches the box: along the cable (from the push button or
  // from the bus), then the LED and the log.
  const send = (t, way, fast, mine) => new Promise((resolve) => {
    const arrive = () => {
      blink();
      toLog(t, mine);
      resolve();
    };
    if (still || !geo || !way) arrive();
    else along(way, fast ? 0.8 : 1.6, arrive, fast ? 400 : 600);
  });

  // The keys switch a light of the landing page's board; the actuator's
  // status follows from the bus.
  const state = new Map();
  for (const k of keys) {
    k.addEventListener('click', () => {
      const a = JSON.parse(k.dataset.key);
      const on = !state.get(a.to);
      state.set(a.to, on);
      k.querySelector('.tz-key-led').classList.toggle('is-on', on);
      const value = on ? words.on : words.off;
      const actuator = script.find((t) => t.to === a.status)?.from || '1.1.10';
      k.classList.add('is-pressed');
      setTimeout(() => k.classList.remove('is-pressed'), 180);
      const led = k.querySelector('.tz-key-led');
      led.classList.add('is-sending');
      setTimeout(() => led.classList.remove('is-sending'), 500);
      send({ from: sensor.dataset.addr, to: a.to, text: a.text, value }, geo?.from, true, true)
        .then(() => new Promise((r) => setTimeout(r, 120)))
        .then(() => send({ from: actuator, to: a.status, text: a.status_text, value }, geo?.in, true, true));
    });
  }

  // The script: irregular like a real line, a status right after its
  // command, then a pause of a moment up to several seconds.
  let n = 0;
  let run = 0;
  const auto = (r) => {
    if (still || r !== run) return;
    const t = script[n++ % script.length];
    const following = script[n % script.length];
    const wait = following.out ? 150 : Math.random() < 0.25 ? 300 : 900 + Math.random() * 4200;
    send(t, geo?.in, false, false).then(() => setTimeout(() => auto(r), wait));
  };
  const start = () => {
    const r = ++run;
    if (!still) setTimeout(() => auto(r), 700);
  };
  motion.addEventListener('change', (e) => {
    still = e.matches;
    start();
  });
  start();
})();
