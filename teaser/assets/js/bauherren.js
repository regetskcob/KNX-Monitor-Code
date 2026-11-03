// Home builders page: house scene for everyday moments and a small floor plan
// in which type and position of the devices change the channel count and the hints.
(function () {
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches;

  function paint(svg, scene) {
    const sky = { night: 'var(--bh-night)', dawn: 'var(--warning-tint, #F6EBD9)', day: 'var(--info-tint, #E2EAF5)' };
    svg.querySelector('.bh-sky').style.fill = sky[scene.sky];
    const sun = svg.querySelector('.bh-sun');
    sun.setAttribute('cx', scene.sun[0]);
    sun.setAttribute('cy', scene.sun[1]);
    sun.classList.toggle('is-moon', scene.sky === 'night');
    svg.querySelectorAll('.bh-light').forEach((el, i) => { el.style.opacity = scene.lights[i]; });
    svg.querySelectorAll('.bh-blind').forEach((el, i) => { el.style.transform = `scaleY(${scene.blinds[i]})`; });
  }

  const S = (sky, sun, lights, blinds) => ({ sky, sun, lights, blinds });
  const hero = document.getElementById('bh-hero');
  if (hero) {
    const loop = [
      S('night', [300, 40], [0, 0, 0, 0], [1, 1, 1, 1]),
      S('dawn', [310, 110], [0.35, 0, 0, 0], [0.4, 1, 1, 1]),
      S('day', [310, 50], [0, 0.2, 0.6, 0.6], [0, 0.2, 0.2, 0.2]),
      S('night', [40, 40], [0, 0, 0.5, 0.8], [1, 1, 0.6, 0.6]),
    ];
    let i = still ? 2 : 0;
    paint(hero, loop[i]);
    if (!still) setInterval(() => { i = (i + 1) % loop.length; paint(hero, loop[i]); }, 2400);
  }

  // Moments
  const box = document.querySelector('.bh-moments');
  if (box) {
    const items = JSON.parse(box.dataset.moments);
    const words = JSON.parse(box.dataset.words);
    const answers = {};
    const tabs = box.querySelector('.bh-tabs');
    const svg = box.querySelector('.bh-scene');
    let current = 0;
    let step = 0;
    let timer = 0;

    function tally() {
      const wishes = new Map();
      items.forEach((m, i) => { if (answers[i] === 'yes') m.wishes.forEach((w) => wishes.set(w.t, w.now)); });
      const now = [...wishes.values()].filter(Boolean).length;
      box.querySelector('.bh-tally').textContent = wishes.size
        ? words.tally.replace('{n}', wishes.size).replace('{now}', now)
        : words.tally_empty;
    }

    function show(i) {
      current = i;
      step = still ? items[i].scenes.length - 1 : 0;
      const m = items[i];
      tabs.querySelectorAll('button').forEach((b, j) => {
        b.setAttribute('aria-selected', j === i);
        b.tabIndex = j === i ? 0 : -1;
      });
      box.querySelector('.bh-moment-title').textContent = m.title;
      box.querySelector('.bh-moment-story').textContent = m.story;
      const list = box.querySelector('.bh-wishes');
      list.replaceChildren(...m.wishes.map((w) => {
        const li = document.createElement('li');
        li.textContent = w.t;
        const tag = document.createElement('span');
        tag.className = `hz-badge ${w.now ? 'hz-badge--warning' : 'hz-badge--positive'}`;
        // Word, symbol and colour as in the app.
        const sign = document.createElement('span');
        sign.className = 'hz-symbol';
        sign.setAttribute('aria-hidden', 'true');
        sign.textContent = w.now ? '\uf083' : '\uf0be';
        tag.append(sign, w.now ? words.now : words.later);
        li.append(' ', tag);
        return li;
      }));
      box.querySelectorAll('[data-answer]').forEach((b) => b.setAttribute('aria-pressed', answers[i] === b.dataset.answer));
      tick();
      clearInterval(timer);
      if (!still) timer = setInterval(() => { step = (step + 1) % items[current].scenes.length; tick(); }, 2400);
    }

    function tick() {
      const sc = items[current].scenes[step];
      paint(svg, S(sc.sky, sc.sun, sc.lights, sc.blinds));
      box.querySelector('.bh-time').textContent = sc.time;
      box.querySelector('.bh-caption-text').textContent = sc.caption;
    }

    items.forEach((m, i) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.role = 'tab';
      b.className = 'bh-tab';
      b.textContent = m.short;
      b.addEventListener('click', () => show(i));
      tabs.append(b);
    });
    tabs.addEventListener('keydown', (e) => {
      const d = { ArrowRight: 1, ArrowLeft: -1 }[e.key];
      if (!d) return;
      const next = (current + d + items.length) % items.length;
      show(next);
      tabs.children[next].focus();
    });
    box.querySelectorAll('[data-answer]').forEach((b) => b.addEventListener('click', () => {
      answers[current] = b.dataset.answer;
      tally();
      show(Math.min(current + 1, items.length - 1));
    }));
    tally();
    show(0);
  }

  // Floor plan
  const plan = document.querySelector('.bh-plan');
  if (plan) {
    const w = JSON.parse(plan.dataset.words);
    const stage = plan.querySelector('.bh-devices');
    const M_PER_UNIT = 6.2 / 520;
    const ROOMS = {
      living: { x: 40, y: 40, w: 520, h: 380 }, kitchen: { x: 560, y: 40, w: 400, h: 260 },
      hall: { x: 420, y: 420, w: 280, h: 180 }, office: { x: 40, y: 420, w: 260, h: 180 },
    };
    plan.querySelector('.bh-rooms').innerHTML = [['living', 250, 120], ['kitchen', 760, 200], ['hall', 560, 520], ['office', 170, 500]]
      .map(([k, x, y]) => `<span style="left:${x / 10}%;top:${y / 6.4}%">${w.rooms[k]}</span>`).join('');
    // The same symbols as in the app (Horizont, icons/material-symbols.json).
    const icons = { light: '\ue90f', socket: '\u{100004}', button: '\ue913', blind: '\ue286' };
    const devices = [
      { id: 'l1', kind: 'light', room: 'living', x: 425, y: 175, mode: 'dim' },
      { id: 'l2', kind: 'light', room: 'living', x: 190, y: 200, mode: 'dim' },
      { id: 'l3', kind: 'light', room: 'kitchen', x: 760, y: 130, mode: 'switch' },
      { id: 's1', kind: 'socket', room: 'living', x: 190, y: 420, mode: 'perm' },
      { id: 's2', kind: 'socket', room: 'living', x: 40, y: 340, mode: 'meter' },
      { id: 's3', kind: 'socket', room: 'kitchen', x: 960, y: 200, mode: 'perm' },
      { id: 'j1', kind: 'blind', room: 'living', x: 230, y: 40, mode: 'roller', height: null },
      { id: 'j2', kind: 'blind', room: 'living', x: 40, y: 150, mode: 'roller', height: null },
      { id: 'j3', kind: 'blind', room: 'kitchen', x: 760, y: 40, mode: 'slat', height: null },
      { id: 't1', kind: 'button', room: 'living', x: 505, y: 420, mode: null, wrong: true, height: 105 },
    ];
    let selected = 't1';
    const res = (n) => Math.ceil(n * 1.3);
    const CYCLE = { light: ['dim', 'switch', 'tw', 'rgb'], socket: ['perm', 'switch', 'meter'], blind: ['roller', 'slat'] };

    function dims(d) {
      const r = ROOMS[d.room];
      const left = d.x - r.x, right = r.x + r.w - d.x, top = d.y - r.y, bottom = r.y + r.h - d.y;
      return {
        hx: left <= right ? r.x : r.x + r.w, vy: top <= bottom ? r.y : r.y + r.h,
        dx: Math.min(left, right), dy: Math.min(top, bottom),
      };
    }
    const metres = (u) => (u * M_PER_UNIT).toFixed(2).replace('.', w.decimal) + ' m';

    function render() {
      stage.replaceChildren(...devices.map((d) => {
        const b = document.createElement('button');
        b.type = 'button';
        b.className = `bh-device${d.id === selected ? ' is-selected' : ''}${d.wrong ? ' is-warn' : ''}`;
        b.style.left = `${d.x / 10}%`;
        b.style.top = `${d.y / 6.4}%`;
        const label = w.kinds[d.kind] + (d.mode ? `, ${w.modes[d.mode]}` : '');
        b.setAttribute('aria-label', label);
        b.title = label;
        b.innerHTML = `<span class="hz-symbol" aria-hidden="true">${icons[d.kind]}</span>`;
        b.addEventListener('click', () => {
          if (selected === d.id && d.mode) d.mode = CYCLE[d.kind][(CYCLE[d.kind].indexOf(d.mode) + 1) % CYCLE[d.kind].length];
          selected = d.id;
          render();
          stage.querySelector('.is-selected').focus();
        });
        return b;
      }));

      const cur = devices.find((d) => d.id === selected);
      const dm = dims(cur);
      plan.querySelector('.bh-dims').innerHTML =
        `<line x1="${dm.hx}" y1="${cur.y}" x2="${cur.x}" y2="${cur.y}"/><line x1="${cur.x}" y1="${dm.vy}" x2="${cur.x}" y2="${cur.y}"/>`;

      const detail = plan.querySelector('.bh-detail');
      detail.innerHTML = '';
      const title = document.createElement('strong');
      title.textContent = w.kinds[cur.kind];
      detail.append(title);
      if (cur.mode) {
        const group = document.createElement('div');
        group.className = 'bh-modes';
        group.role = 'group';
        CYCLE[cur.kind].forEach((mode) => {
          const b = document.createElement('button');
          b.type = 'button';
          b.textContent = w.modes[mode];
          b.setAttribute('aria-pressed', cur.mode === mode);
          b.addEventListener('click', () => {
            cur.mode = mode;
            render();
            plan.querySelector('.bh-modes [aria-pressed="true"]').focus();
          });
          group.append(b);
        });
        detail.append(group);
      }
      const rows = document.createElement('p');
      rows.className = 't-caption';
      rows.textContent = (cur.height ? `${w.height}: ${cur.height} cm · ` : '') + `${w.distance}: ${metres(dm.dx)} / ${metres(dm.dy)}`;
      detail.append(rows);

      const n = (mode) => devices.filter((d) => d.mode === mode);
      const count = [
        [w.count.switch, res(n('switch').length)],
        [w.count.dim, res(n('dim').length)],
        [w.count.blind, res(n('roller').length + n('slat').length)],
        [w.count.led, res(n('tw').length * 2 + n('rgb').length * 3)],
        [w.count.meter, res(n('meter').length)],
        [w.count.perm, n('perm').length],
      ];
      plan.querySelector('.bh-count').innerHTML = count.map(([t, v]) => `<div><dt>${t}</dt><dd class="t-data">${v}</dd></div>`).join('');

      const hint = plan.querySelector('.bh-hint');
      const button = devices.find((d) => d.id === 't1');
      hint.replaceChildren();
      hint.classList.toggle('is-ok', !button.wrong);
      hint.append(button.wrong ? w.hint_wrong : w.hint_ok);
      if (button.wrong) {
        const fix = document.createElement('button');
        fix.type = 'button';
        fix.className = 'hz-button hz-button--secondary hz-button--dense';
        fix.textContent = w.hint_fix;
        fix.addEventListener('click', () => { button.x = 545; button.wrong = false; selected = 't1'; render(); stage.querySelector('.is-selected').focus(); });
        hint.append(' ', fix);
      }
    }
    render();
  }
})();
