/**
 * AI Radar operator console (T-175) — hash router, fetch JSON/Markdown APIs.
 */

const $app = document.getElementById("app");
const $nav = document.getElementById("nav");

const NAV = [
  { hash: "#/", label: "Painel" },
  { hash: "#/digests", label: "Digests" },
  { hash: "#/sources", label: "Fontes" },
];

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** Minimal Markdown → HTML (digest reports; server-generated content). */
function renderMarkdown(md) {
  const lines = md.split("\n");
  const out = [];
  let inList = false;

  const closeList = () => {
    if (inList) {
      out.push("</ul>");
      inList = false;
    }
  };

  for (const raw of lines) {
    const line = raw.trimEnd();
    if (line.startsWith("# ")) {
      closeList();
      out.push(`<h1>${escapeHtml(line.slice(2))}</h1>`);
    } else if (line.startsWith("## ")) {
      closeList();
      out.push(`<h2>${escapeHtml(line.slice(3))}</h2>`);
    } else if (line.startsWith("### ")) {
      closeList();
      out.push(`<h3>${inlineFormat(line.slice(4))}</h3>`);
    } else if (line.startsWith("- ")) {
      if (!inList) {
        out.push("<ul>");
        inList = true;
      }
      out.push(`<li>${inlineFormat(line.slice(2))}</li>`);
    } else if (line === "") {
      closeList();
    } else if (line === "---" || line === "***") {
      closeList();
      out.push("<hr />");
    } else {
      closeList();
      out.push(`<p>${inlineFormat(line)}</p>`);
    }
  }
  closeList();
  return out.join("\n");
}

function inlineFormat(text) {
  let s = escapeHtml(text);
  s = s.replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>");
  s = s.replace(
    /\[([^\]]+)\]\(([^)]+)\)/g,
    '<a href="$2" target="_blank" rel="noopener">$1</a>',
  );
  return s;
}

async function apiJson(path) {
  const res = await fetch(path, {
    headers: { Accept: "application/json" },
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`${res.status} ${path}: ${body.slice(0, 200)}`);
  }
  return res.json();
}

async function apiMarkdown(path) {
  const res = await fetch(path, {
    headers: { Accept: "text/markdown" },
  });
  if (!res.ok) {
    throw new Error(`${res.status} ${path}`);
  }
  return res.text();
}

function setNav(activeHash) {
  $nav.innerHTML = NAV.map(
    (item) =>
      `<a href="${item.hash}" class="${item.hash === activeHash ? "active" : ""}">${item.label}</a>`,
  ).join("");
}

function parseRoute() {
  const hash = location.hash || "#/";
  const digestMatch = hash.match(/^#\/digests\/([0-9a-f-]{36})$/i);
  if (digestMatch) {
    return { page: "digest", id: digestMatch[1] };
  }
  if (hash === "#/digests") return { page: "digests" };
  if (hash === "#/sources") return { page: "sources" };
  return { page: "home" };
}

function card(label, value) {
  return `<div class="card"><div class="card-label">${label}</div><div class="card-value">${value}</div></div>`;
}

async function renderHome() {
  setNav("#/");
  const stats = await apiJson("/stats");
  let latest = null;
  try {
    const list = await apiJson("/digests");
    latest = list.items && list.items[0] ? list.items[0] : null;
  } catch {
    /* optional */
  }

  const latestBlock = latest
    ? `<p class="muted">Último digest: <a href="#/digests/${latest.id}">${escapeHtml(
        latest.digest_type,
      )}</a> — ${new Date(latest.generated_at).toLocaleString("pt-BR")}</p>
       <a class="btn" href="#/digests/${latest.id}">Abrir relatório</a>`
    : `<p class="muted">Nenhum digest gerado ainda. Use <code>POST /digest/run</code> ou o CronJob.</p>`;

  const cards = [
    card("Fontes", stats.sources_total),
    card("Fontes ativas", stats.sources_enabled),
    card("Itens brutos", stats.raw_items_total),
    card("Pendentes extract", stats.raw_items_pending),
  ].join("");

  $app.innerHTML = `<h1 class="section-title">Painel</h1><div class="cards">${cards}</div>${latestBlock}`;
}

async function renderDigests() {
  setNav("#/digests");
  const list = await apiJson("/digests");
  if (!list.items || list.items.length === 0) {
    $app.innerHTML =
      '<h1 class="section-title">Digests</h1><p class="muted">Nenhum digest salvo.</p>';
    return;
  }
  const rows = list.items
    .map((d) => {
      const when = new Date(d.generated_at).toLocaleString("pt-BR");
      const badge =
        d.digest_type === "weekly"
          ? '<span class="badge badge-weekly">weekly</span>'
          : '<span class="badge badge-daily">daily</span>';
      return `<tr><td>${badge}</td><td>${when}</td><td><a href="#/digests/${d.id}">Abrir</a></td></tr>`;
    })
    .join("");
  $app.innerHTML = `<h1 class="section-title">Digests</h1><div class="table-wrap"><table><thead><tr><th>Tipo</th><th>Gerado em</th><th></th></tr></thead><tbody>${rows}</tbody></table></div>`;
}

async function renderDigest(id) {
  setNav("#/digests");
  const md = await apiMarkdown(`/digests/${id}`);
  $app.innerHTML = `<p><a href="#/digests">← Voltar</a></p><article class="digest-article">${renderMarkdown(md)}</article>`;
}

async function renderSources() {
  setNav("#/sources");
  const data = await apiJson("/sources");
  if (!data.items || data.items.length === 0) {
    $app.innerHTML =
      '<h1 class="section-title">Fontes</h1><p class="muted">Nenhuma fonte cadastrada. Use <code>POST /sources</code>.</p>';
    return;
  }
  const rows = data.items
    .map((s) => {
      const enabled = s.enabled
        ? '<span style="color:var(--ok)">sim</span>'
        : '<span style="color:var(--muted)">não</span>';
      return `<tr>
        <td>${escapeHtml(s.name)}</td>
        <td><code>${escapeHtml(s.source_type)}</code></td>
        <td>${enabled}</td>
        <td>${s.poll_interval_minutes} min</td>
        <td><a href="${escapeHtml(s.url)}" target="_blank" rel="noopener">link</a></td>
      </tr>`;
    })
    .join("");
  $app.innerHTML = `<h1 class="section-title">Fontes</h1><div class="table-wrap"><table><thead><tr><th>Nome</th><th>Tipo</th><th>Ativa</th><th>Poll</th><th>URL</th></tr></thead><tbody>${rows}</tbody></table></div>`;
}

async function render() {
  const route = parseRoute();
  $app.innerHTML = '<p class="loading">Carregando…</p>';
  try {
    if (route.page === "home") await renderHome();
    else if (route.page === "digests") await renderDigests();
    else if (route.page === "digest") await renderDigest(route.id);
    else if (route.page === "sources") await renderSources();
  } catch (err) {
    $app.innerHTML = `<p class="error">${escapeHtml(err.message)}</p>`;
  }
}

window.addEventListener("hashchange", render);
render();
