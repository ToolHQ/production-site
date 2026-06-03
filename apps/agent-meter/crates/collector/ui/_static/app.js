// agent-meter shared js
(function(){
  const root = document.documentElement;
  const stored = localStorage.getItem('am-theme');
  if (stored) root.setAttribute('data-theme', stored);
  window.amToggleTheme = function(){
    const cur = root.getAttribute('data-theme') || 'dark';
    const next = cur === 'dark' ? 'light' : 'dark';
    root.setAttribute('data-theme', next);
    localStorage.setItem('am-theme', next);
  };

  // copy buttons
  document.addEventListener('click', (e) => {
    const btn = e.target.closest('[data-copy]');
    if (!btn) return;
    e.preventDefault();
    const txt = btn.getAttribute('data-copy');
    navigator.clipboard.writeText(txt).then(() => {
      const old = btn.textContent;
      btn.textContent = 'Copied!';
      setTimeout(() => btn.textContent = old, 1200);
    });
  });

  // sidebar collapse
  window.amToggleSidebar = function(){
    const app = document.querySelector('.am-app');
    if (!app) return;
    const collapsed = app.getAttribute('data-collapsed') === 'true';
    app.setAttribute('data-collapsed', collapsed ? 'false' : 'true');
    localStorage.setItem('am-sidebar-collapsed', collapsed ? 'false' : 'true');
  };

  document.addEventListener('DOMContentLoaded', () => {
    const app = document.querySelector('.am-app');
    if (app && localStorage.getItem('am-sidebar-collapsed') === 'true') {
      app.setAttribute('data-collapsed', 'true');
    }

    // load /api/me into user menu
    fetch('/api/me', {credentials:'include'}).then(r => r.ok ? r.json() : null).then(me => {
      const slot = document.getElementById('amUserSlot');
      if (!slot) return;
      if (me) {
        const name = me.display_name || me.github_login || me.email;
        slot.innerHTML = `
          <a class="am-btn am-btn-ghost am-btn-sm" href="/auth/logout" title="Sign out">
            ${me.avatar_url ? `<img src="${me.avatar_url}" alt="" style="width:20px;height:20px;border-radius:50%">` : '<svg class="am-icon"><use href="/_static/icons.svg#i-user"/></svg>'}
            <span>${name}</span>
          </a>`;
      } else {
        slot.innerHTML = `<a class="am-btn am-btn-secondary am-btn-sm" href="/login"><svg class="am-icon"><use href="/_static/icons.svg#i-github"/></svg>Sign in</a>`;
      }
    }).catch(()=>{});
  });

  // sparkline helper: amSpark(values, w, h, color)
  window.amSpark = function(values, w=80, h=22, color='var(--am-accent)'){
    if (!values || !values.length) return '';
    const max = Math.max(...values, 1);
    const min = Math.min(...values, 0);
    const range = (max - min) || 1;
    const step = w / Math.max(values.length - 1, 1);
    const pts = values.map((v, i) => `${i*step},${h - ((v - min)/range) * h}`).join(' ');
    const last = values[values.length-1];
    const lx = (values.length-1) * step;
    const ly = h - ((last - min)/range) * h;
    return `<svg class="am-spark" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none"><polyline points="${pts}" fill="none" stroke="${color}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><circle cx="${lx}" cy="${ly}" r="2" fill="${color}"/></svg>`;
  };

  // delta pill
  window.amDelta = function(curr, prev){
    if (prev == null || prev === 0) return '';
    const d = ((curr - prev) / Math.abs(prev)) * 100;
    const cls = d > 0.5 ? 'up' : d < -0.5 ? 'down' : 'flat';
    const arrow = d > 0.5 ? '▲' : d < -0.5 ? '▼' : '—';
    return `<span class="am-delta ${cls}">${arrow} ${Math.abs(d).toFixed(1)}%</span>`;
  };

  // money formatter
  window.amMoney = function(n){
    if (n == null) return '$0';
    if (n >= 1000) return '$' + n.toFixed(0).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    if (n >= 10) return '$' + n.toFixed(2);
    if (n >= 1) return '$' + n.toFixed(3);
    return '$' + n.toFixed(4);
  };
  window.amNum = function(n){
    if (n == null) return '0';
    if (n >= 1e6) return (n/1e6).toFixed(1) + 'M';
    if (n >= 1e3) return (n/1e3).toFixed(1) + 'K';
    return Math.round(n).toLocaleString();
  };
})();
