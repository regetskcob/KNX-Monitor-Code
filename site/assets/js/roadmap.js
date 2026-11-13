// Roadmap and changelog (layouts/roadmap.html): a pulse runs down the cable,
// around its bends, as on the home page's thread; and on load the page glides to
// "today", so it shows that the line goes on in both directions. Not with an
// anchor in the address (a link to one version) and not once the reader has
// scrolled; with reduced motion it jumps instead of gliding.
(() => {
  const today = document.getElementById('today');
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const go = () => {
    if (!today || location.hash || scrollY > 8) return;
    // "Today" a third down the window: the future stays in sight above it.
    const end = Math.max(0, today.getBoundingClientRect().top + scrollY - innerHeight / 3);
    if (still) return scrollTo(0, end);
    // Its own glide (scrollTo with behavior: smooth does not run everywhere):
    // 1.4 s, eased at both ends, given up as soon as the reader takes over.
    const t0 = performance.now();
    let on = true;
    const stop = () => { on = false; };
    for (const e of ['wheel', 'touchstart', 'keydown', 'pointerdown']) addEventListener(e, stop, { once: true, passive: true });
    const step = (t) => {
      if (!on) return;
      const k = Math.min(1, (t - t0) / 1400);
      scrollTo(0, end * (k < 0.5 ? 4 * k * k * k : 1 - (-2 * k + 2) ** 3 / 2));
      if (k < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
    // Where frames do not run (a hidden tab), arrive anyway.
    setTimeout(() => { if (on && Math.abs(scrollY - end) > 4) scrollTo(0, end); on = false; }, 2000);
  };
  // After the first paint, so the start of the page is seen for a moment.
  addEventListener('load', () => setTimeout(go, still ? 0 : 600), { once: true });

  // The pulse: along the cable's segments, each entry's node column giving
  // the x, a crossing (.rm-cross) the bend in its middle. 90 px a second.
  const line = document.querySelector('.rm-line');
  if (!line || still || !line.animate) return;
  const dot = line.appendChild(document.createElement('span'));
  dot.className = 'rm-pulse';
  dot.setAttribute('aria-hidden', 'true');
  let run = null;
  const lay = () => {
    run?.cancel();
    const o = line.getBoundingClientRect();
    const pts = [];
    let bend = null;
    for (const li of line.children) {
      if (li === dot) continue;
      const r = li.getBoundingClientRect();
      if (!r.height) continue;
      if (li.classList.contains('rm-cross')) {
        bend = r.top - o.top + r.height / 2;
        if (pts.length) pts.push([pts.at(-1)[0], bend]);
        continue;
      }
      const n = li.querySelector('.rm-node').getBoundingClientRect();
      const x = n.left - o.left + n.width / 2;
      pts.push([x, bend ?? r.top - o.top], [x, r.bottom - o.top]);
      bend = null;
    }
    if (pts.length < 2) return;
    pts.at(-1)[1] -= 24;
    const len = pts.map((p, i) => (i ? Math.hypot(p[0] - pts[i - 1][0], p[1] - pts[i - 1][1]) : 0));
    const total = len.reduce((a, b) => a + b, 0);
    let at = 0;
    const frames = pts.map((p, i) => {
      at += len[i];
      return { transform: `translate(${p[0]}px, ${p[1]}px)`, offset: at / total, opacity: i === 0 || i === pts.length - 1 ? 0 : 1 };
    });
    run = dot.animate(frames, { duration: (total / 90) * 1000, iterations: Infinity });
  };
  addEventListener('load', lay, { once: true });
  let wait = 0;
  addEventListener('resize', () => { clearTimeout(wait); wait = setTimeout(lay, 200); });
  line.addEventListener('toggle', lay, true);
})();
