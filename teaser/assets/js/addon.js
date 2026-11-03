// Add-on page: a key on the glass push button sends a telegram; the watcher
// "<name>" fires knx_monitor_watcher, shown like Home Assistant's event view.
// With notifications on, the notification that would come on top shows too.
(function () {
  const demo = document.querySelector('.tz-demo');
  if (!demo) return;
  const words = JSON.parse(demo.dataset.demo);
  const list = demo.querySelector('.tz-demo-events');
  const note = demo.querySelector('.tz-demo-note');
  const toggle = demo.querySelector('.tz-demo-toggle input');
  const state = {};
  let hide = 0;

  function fire(key, on) {
    const data = {
      watcher_id: key.id,
      name: key.name,
      label: key.address + ' ' + key.name,
      address: key.address,
      source: '1.1.30',
      raw: on ? '01' : '00',
      installation: words.installation,
    };
    const li = document.createElement('li');
    const time = new Date();
    li.innerHTML = '<span class="tz-demo-time"></span><pre></pre>';
    li.querySelector('.tz-demo-time').textContent =
      words.fired + ' ' + time.toLocaleTimeString(document.documentElement.lang, { hour12: false });
    li.querySelector('pre').textContent = JSON.stringify({ event_type: 'knx_monitor_watcher', data }, null, 2);
    list.querySelector('.tz-demo-empty')?.remove();
    list.prepend(li);
    while (list.children.length > 2) list.lastElementChild.remove();
    if (toggle.checked) {
      note.textContent = words.watcher + ': ' + key.name + ' · ' + key.address + ' · ' + (on ? words.on : words.off);
      note.hidden = false;
      clearTimeout(hide);
      hide = setTimeout(() => { note.hidden = true; }, 4000);
    }
  }

  demo.querySelectorAll('.tz-key').forEach((k) => {
    const key = JSON.parse(k.dataset.key);
    k.addEventListener('click', () => {
      const on = !state[key.id];
      state[key.id] = on;
      k.querySelector('.tz-key-led').classList.toggle('is-on', on);
      fire(key, on);
    });
  });
  toggle.addEventListener('change', () => { if (!toggle.checked) note.hidden = true; });
})();
