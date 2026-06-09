/**
 * AI Radar operator console (T-175) — hash router, fetch JSON/Markdown APIs.
 */

const $app = document.getElementById("app");
const $nav = document.getElementById("nav");

const NAV = [
  { hash: "#/", label: "Painel" },
  { hash: "#/items", label: "Explorer" },
  { hash: "#/compare", label: "Comparator" },
  { hash: "#/digests", label: "Digests" },
  { hash: "#/sources", label: "Fontes" },
  { hash: "#/reports/duplicates", label: "Duplicatas" },
  { hash: "#/reports/semantic-duplicates", label: "Dup. semântica" },
  { hash: "#/reports/divergence", label: "Divergência" },
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
    } else if (line.startsWith("- ") || line.startsWith("  - ")) {
      if (!inList) {
        out.push("<ul>");
        inList = true;
      }
      const bullet = line.startsWith("  - ") ? line.slice(4) : line.slice(2);
      out.push(`<li>${inlineFormat(bullet)}</li>`);
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
  if (!path.startsWith("/")) throw new Error("Invalid API path");
  const res = await fetch(new URL(path, window.location.origin), {
    headers: { Accept: "application/json" },
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`${res.status} ${path}: ${body.slice(0, 200)}`);
  }
  return res.json();
}

async function apiPost(path, body) {
  if (!path.startsWith("/")) throw new Error("Invalid API path");
  const res = await fetch(new URL(path, window.location.origin), {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`${res.status} ${path}: ${text.slice(0, 200)}`);
  }
  return res.json();
}

function setNav(activeHash) {
  $nav.innerHTML = NAV.map(
    (item) =>
      `<a href="${item.hash}" class="${item.hash === activeHash ? "active" : ""}">${item.label}</a>`,
  ).join("");
}

function decisionBadge(decision) {
  const d = String(decision || "").toLowerCase();
  return `<span class="badge badge-decision badge-${escapeHtml(d)}">${escapeHtml(d)}</span>`;
}

const STARS_TIER_PT = {
  niche: "Niche",
  growing: "Growing",
  popular: "Popular",
  viral: "Viral",
};

const ACTIVITY_TIER_PT = {
  active: "Ativo",
  moderate: "Moderado",
  stale: "Stale",
  dormant: "Dormant",
};

const VELOCITY_TIER_PT = {
  spike: "Pico 7d",
  growing: "Subindo",
  flat: "Estável",
  declining: "Queda",
  unknown: "?",
};

function embeddingBadge(hasEmbedding) {
  if (hasEmbedding === false) {
    return '<span class="badge badge-embed-missing" title="Sem vetor para busca semântica">sem vetor</span>';
  }
  return "";
}

function signalBadges(adoption, qualityWarn) {
  const parts = [];
  if (adoption?.stars_tier) {
    const t = adoption.stars_tier;
    parts.push(
      `<span class="badge badge-tier badge-tier-${escapeHtml(t)}" title="GitHub stars">${escapeHtml(STARS_TIER_PT[t] || t)}${adoption.stars != null ? ` · ${fmtNum(adoption.stars)}` : ""}</span>`,
    );
  }
  if (adoption?.velocity_tier) {
    const v = adoption.velocity_tier;
    parts.push(
      `<span class="badge badge-velocity badge-velocity-${escapeHtml(v)}">${escapeHtml(VELOCITY_TIER_PT[v] || v)}</span>`,
    );
  }
  if (adoption?.activity_tier) {
    const a = adoption.activity_tier;
    parts.push(
      `<span class="badge badge-activity badge-activity-${escapeHtml(a)}">${escapeHtml(ACTIVITY_TIER_PT[a] || a)}</span>`,
    );
  }
  if (qualityWarn) {
    parts.push(`<span class="badge badge-quality-warn">low conf.</span>`);
  }
  return parts.length ? parts.join(" ") : `<span class="muted">—</span>`;
}

function relatedEmptyHint(related) {
  if (!related) {
    return "Não foi possível carregar vizinhos semânticos.";
  }
  if (!related.has_embedding) {
    return 'Este item ainda não tem embedding. Rode <code>ai-radar embed</code> ou aguarde o CronJob <code>ai-radar-embed</code>.';
  }
  if (related.count > 0) {
    return "";
  }
  const min = related.min_similarity ?? 0.55;
  const best =
    related.best_similarity != null ? similarityPct(related.best_similarity) : null;
  const bestBit = best ? ` (melhor candidato no pool: ${best})` : "";
  switch (related.empty_reason) {
    case "no_embedding":
      return "Sem embedding para este item.";
    case "insufficient_pool":
      return 'Poucos embeddings no cluster — veja cobertura na <a href="#/">home</a> e rode o backfill de embed.';
    case "below_threshold":
      if (related.same_category) {
        return `Nenhum vizinho na mesma categoria acima de ${Math.round(min * 100)}% de similaridade${bestBit}. Desmarque “só mesma categoria” para ampliar o pool.`;
      }
      return `Nenhum vizinho acima de ${Math.round(min * 100)}% de similaridade${bestBit}.`;
    default:
      if (related.same_category) {
        return "Nenhum vizinho na mesma categoria. Tente buscar em todas as categorias.";
      }
      return `Nenhum vizinho semântico próximo o suficiente${bestBit}.`;
  }
}

function renderRelatedPanelContent(related) {
  if (!related?.items?.length) {
    return `<p class="muted item-related-empty">${relatedEmptyHint(related)}</p>`;
  }
  return `<ul class="item-related-list">${related.items
    .map((hit) => {
      const it = hit.item || hit;
      const name = it.tool_name || it.summary?.slice(0, 48) || it.extracted_item_id;
      return `<li>
        <a href="#/items/${it.extracted_item_id}">${escapeHtml(name)}</a>
        <span class="badge badge-similarity" title="similaridade vetorial">${similarityPct(hit.similarity)}</span>
        ${it.category ? `<span class="muted"> · ${escapeHtml(it.category)}</span>` : ""}
      </li>`;
    })
    .join("")}</ul>`;
}

function renderRelatedPanel(related, itemId) {
  const sameCategory = related?.same_category !== false;
  const minPct = Math.round((related?.min_similarity ?? 0.55) * 100);
  return itemSection(
    "Ferramentas relacionadas",
    `<div class="item-related-panel" data-item-id="${escapeHtml(itemId)}">
      <label class="item-related-toggle">
        <input type="checkbox" id="related-same-category" ${sameCategory ? "checked" : ""} />
        Só mesma categoria
      </label>
      <div id="related-panel-body">${renderRelatedPanelContent(related)}</div>
      <p class="muted item-related-hint">Vizinhos por embedding · limiar mínimo ${minPct}%</p>
    </div>`,
  );
}

function bindRelatedPanel(itemId) {
  const cb = document.getElementById("related-same-category");
  const body = document.getElementById("related-panel-body");
  if (!cb || !body) {
    return;
  }
  cb.addEventListener("change", async () => {
    body.innerHTML = '<p class="muted">Carregando…</p>';
    const same = cb.checked;
    try {
      const related = await apiJson(
        `/items/${itemId}/related?limit=8&same_category=${same ? "true" : "false"}`,
      );
      body.innerHTML = renderRelatedPanelContent(related);
    } catch {
      body.innerHTML = renderRelatedPanelContent({
        has_embedding: false,
        items: [],
        count: 0,
      });
    }
  });
}

function renderItemSignalsPanel(ex, latestScore) {
  const adoption = ex.metadata_json?.adoption;
  const sourceHealth = ex.metadata_json?.source_health;
  const calibrated = latestScore?.metadata_json?.feedback_calibration === true;
  const qualityWarn = ex.metadata_json?.quality_warn === true;
  const rows = [];
  if (adoption) {
    if (adoption.stars != null) {
      let line = `⭐ ${fmtNum(adoption.stars)} stars`;
      if (adoption.stars_delta_7d != null) {
        line += ` · Δ7d ${adoption.stars_delta_7d >= 0 ? "+" : ""}${fmtNum(adoption.stars_delta_7d)}`;
      }
      rows.push(["Popularidade", line]);
    }
    if (adoption.stars_tier) {
      rows.push(["Faixa stars", STARS_TIER_PT[adoption.stars_tier] || adoption.stars_tier]);
    }
    if (adoption.velocity_tier) {
      rows.push([
        "Tendência 7d",
        VELOCITY_TIER_PT[adoption.velocity_tier] || adoption.velocity_tier,
      ]);
    }
    if (adoption.activity_tier) {
      rows.push([
        "Atividade repo",
        ACTIVITY_TIER_PT[adoption.activity_tier] || adoption.activity_tier,
      ]);
    }
  }
  if (sourceHealth?.tier) {
    rows.push(["Saúde da fonte", sourceHealthBadge(sourceHealth.tier)]);
  }
  if (qualityWarn) {
    rows.push(["Extract", '<span class="badge badge-quality-warn">quality warn</span>']);
  }
  if (calibrated) {
    rows.push(["Score", '<span class="badge badge-calibrated">calibrado por feedback</span>']);
  }
  if (!rows.length) {
    return "";
  }
  return itemSection(
    "Sinais (Fase 17)",
    `<div class="item-signals-grid">${itemDl(rows)}</div>`,
  );
}

function scorePct(score) {
  if (score == null || Number.isNaN(Number(score))) return "—";
  return `${Math.round(Number(score) * 100)}%`;
}

function similarityPct(sim) {
  if (sim == null || Number.isNaN(Number(sim))) return "—";
  return `${Math.round(Number(sim) * 100)}%`;
}

let semanticSearchTimer = null;

const RULE_LABELS_PT = {
  problem_filled: "Problema e caso de uso claros",
  self_hosted: "Compatível com self-host no cluster",
  k8s_fit: "Encaixa em Kubernetes / plataforma",
  structured_identity: "Nome e categoria estruturados",
  rich_summary: "Resumo rico (sinal forte)",
  category_present: "Categoria identificada",
  cost_productivity: "Ângulo de custo / produtividade",
  permissive_license: "Licença permissiva conhecida",
  mature: "Maturidade estável",
  low_risk: "Risco operacional baixo",
  deep_stack_notes: "Notas de stack / ops detalhadas",
  saas_lockin: "Apenas SaaS (sem self-host)",
  high_risk: "Risco operacional alto",
  deprecated: "Projeto obsoleto / deprecated",
  superficial: "Identidade fraca / resumo curto",
  proprietary_license: "Licença proprietária / fechada",
  weak_signals: "Metadados fracos (stack/categoria)",
  experimental: "Maturidade experimental",
  hype: "Texto promocional sem profundidade",
  missing_license: "Licença não informada",
};

const GENERIC_NEXT_STEPS = new Set([
  "Promote to team standard; track adoption metrics and owner.",
  "Run a time-boxed spike in a sandbox cluster before wide rollout.",
  "No immediate action — revisit next digest cycle unless signals change.",
  "Archive; do not spend further review time unless new evidence appears.",
]);

const MATURITY_PT = {
  experimental: "Experimental",
  beta: "Beta",
  stable: "Estável",
  mature: "Maduro",
  deprecated: "Obsoleto",
};

const RISK_PT = { low: "Baixo", medium: "Médio", high: "Alto" };

function jsonStringList(v) {
  if (!v) return [];
  if (Array.isArray(v)) {
    return v.map((x) => String(x).trim()).filter(Boolean);
  }
  return [];
}

function humanizeReason(raw) {
  const trimmed = String(raw || "").trim();
  const weightMatch = trimmed.match(/^([+-])(\d+)\s*(.*)$/s);
  let weight = null;
  let rest = trimmed;
  if (weightMatch) {
    weight = Number(weightMatch[2]) * (weightMatch[1] === "-" ? -1 : 1);
    rest = weightMatch[3].trim();
  }
  const bracket = rest.match(/^\[([^\]]+)\]\s*(.*)$/s);
  if (bracket) {
    const label = RULE_LABELS_PT[bracket[1]] || bracket[1].replace(/_/g, " ");
    if (weight != null) return `${weight > 0 ? "+" : ""}${weight} ${label}`;
    return label;
  }
  return trimmed;
}

function isGenericNextStep(s) {
  return GENERIC_NEXT_STEPS.has(String(s || "").trim());
}

function fmtBool(v) {
  if (v === true) return "Sim";
  if (v === false) return "Não";
  return "—";
}

function fmtLabel(map, key) {
  if (!key) return "—";
  return map[String(key).toLowerCase()] || String(key);
}

function fmtDate(iso) {
  if (!iso) return "—";
  return new Date(iso).toLocaleString("pt-BR");
}

function scorePoints(meta) {
  const p = meta?.points;
  return typeof p === "number" && Number.isFinite(p) ? Math.round(p) : null;
}

function itemSection(title, inner) {
  if (!inner || !String(inner).trim()) return "";
  return `<section class="item-section"><h2 class="item-section-title">${title}</h2>${inner}</section>`;
}

function itemDl(rows) {
  const cells = rows
    .filter(([, v]) => v != null && String(v).trim() !== "" && v !== "—")
    .map(
      ([k, v]) =>
        `<div class="item-dl-row"><dt>${escapeHtml(k)}</dt><dd>${v}</dd></div>`,
    )
    .join("");
  if (!cells) return "";
  return `<dl class="item-dl">${cells}</dl>`;
}

function itemTextBlock(label, text) {
  if (!text || !String(text).trim()) return "";
  return `<div class="item-text-block"><span class="digest-label">${escapeHtml(label)}</span><p>${escapeHtml(text)}</p></div>`;
}

function parseRoute() {
  const hash = location.hash || "#/";
  const itemMatch = hash.match(/^#\/items\/([0-9a-f-]{36})$/i);
  if (itemMatch) {
    return { page: "item", id: itemMatch[1] };
  }
  const digestMatch = hash.match(/^#\/digests\/([0-9a-f-]{36})$/i);
  if (digestMatch) {
    return { page: "digest", id: digestMatch[1] };
  }
  if (hash === "#/items") return { page: "items" };
  if (hash === "#/digests") return { page: "digests" };
  if (hash === "#/sources") return { page: "sources" };
  if (hash === "#/reports/duplicates") return { page: "reports-duplicates" };
  if (hash === "#/reports/semantic-duplicates") return { page: "reports-semantic-duplicates" };
  if (hash === "#/reports/divergence") return { page: "reports-divergence" };
  if (hash.startsWith("#/compare")) {
    const q = hash.includes("?") ? hash.slice(hash.indexOf("?") + 1) : "";
    const category = new URLSearchParams(q).get("category") || "";
    return { page: "compare", category };
  }
  return { page: "home" };
}

function card(label, value) {
  return `<div class="card"><div class="card-label">${label}</div><div class="card-value">${value}</div></div>`;
}

function fmtNum(n) {
  return new Intl.NumberFormat("pt-BR").format(Number(n) || 0);
}

function kpiCard(icon, label, value, hint, extraClass = "") {
  return `<article class="kpi-card ${extraClass}">
    <div class="kpi-icon" aria-hidden="true">${icon}</div>
    <div class="kpi-label">${escapeHtml(label)}</div>
    <div class="kpi-value">${fmtNum(value)}</div>
    ${hint ? `<p class="kpi-hint">${escapeHtml(hint)}</p>` : ""}
  </article>`;
}

async function renderHome() {
  setNav("#/");
  const [stats, itemsRes, digestsRes] = await Promise.all([
    apiJson("/stats"),
    apiJson("/items?limit=1").catch(() => ({ total: 0 })),
    apiJson("/digests").catch(() => ({ items: [] })),
  ]);

  const latest =
    digestsRes.items && digestsRes.items[0] ? digestsRes.items[0] : null;
  const scoredTotal = itemsRes.total ?? 0;
  const pending = stats.raw_items_pending ?? 0;
  const rawTotal = stats.raw_items_total ?? 0;
  const processed = Math.max(0, rawTotal - pending);
  const donePct = rawTotal > 0 ? Math.round((processed / rawTotal) * 100) : 0;
  const queuePct = rawTotal > 0 ? 100 - donePct : 0;
  const pendingHigh = pending > 100;
  const emb = stats.embeddings;
  const embCard = emb
    ? (() => {
        const pct = Math.round(emb.coverage_pct ?? 0);
        const low = pct < 50 && (emb.embeddings_pending ?? 0) > 0;
        return kpiCard(
          "🧠",
          "Embeddings",
          emb.embeddings_total,
          `${pct}% de ${fmtNum(emb.embeddings_eligible)} elegíveis · ${fmtNum(emb.embeddings_pending)} na fila embed`,
          low ? "kpi-card--pending" : "",
        );
      })()
    : "";

  const digestPanel = latest
    ? `<div class="digest-feature">
        <span class="digest-feature-type">📡 Último relatório · ${escapeHtml(
          digestTypeLabel(latest.digest_type),
        )}</span>
        <p class="digest-feature-date">${fmtDate(latest.generated_at)}</p>
        <div class="digest-feature-actions">
          <a class="btn" href="#/digests/${latest.id}">Abrir digest</a>
          <a class="btn btn-ghost" href="#/digests">Ver todos</a>
        </div>
      </div>`
    : `<p class="muted">Nenhum digest ainda. O CronJob semanal ou <code>POST /digest/run</code> gera o primeiro relatório.</p>`;

  $app.innerHTML = `
    <header class="home-hero">
      <h1>Curadoria de IA com <span>radar operacional</span></h1>
      <p class="home-lead">
        Coleta RSS e GitHub, extrai sinais com LLM, pontua e publica digests para decisão de adoção no cluster.
      </p>
      <div class="home-status-row">
        <span class="status-pill ${pendingHigh ? "status-pill--warn" : ""}">
          ${pendingHigh ? "Fila de extract ativa" : "Pipeline saudável"}
        </span>
        <span class="muted">${fmtNum(scoredTotal)} ferramentas scored</span>
      </div>
    </header>

    <div class="kpi-grid">
      ${kpiCard("📡", "Fontes monitoradas", stats.sources_total, `${fmtNum(stats.sources_enabled)} ativas`)}
      ${kpiCard("📥", "Itens coletados", rawTotal, "raw_items no Postgres")}
      ${kpiCard("⚡", "Scored no explorer", scoredTotal, "prontos para revisão")}
      ${kpiCard("⏳", "Pendentes extract", pending, "aguardando LLM", "kpi-card--pending")}
      ${embCard}
    </div>

    <div class="home-panels">
      <section class="panel">
        <h2 class="panel-title">Pipeline de ingestão</h2>
        <div class="pipeline-bar" role="img" aria-label="Progresso extract ${donePct}% processado">
          <div class="pipeline-seg pipeline-seg--done" style="width:${donePct}%"></div>
          <div class="pipeline-seg pipeline-seg--queue" style="width:${queuePct}%"></div>
        </div>
        <div class="pipeline-legend">
          <span><span class="dot dot--done"></span> Processados (${fmtNum(processed)})</span>
          <span><span class="dot dot--queue"></span> Na fila (${fmtNum(pending)})</span>
        </div>
      </section>
      <section class="panel">
        <h2 class="panel-title">Digest em destaque</h2>
        ${digestPanel}
      </section>
    </div>

    <nav class="quick-links" aria-label="Atalhos">
      <a class="quick-link" href="#/items">
        <strong>Explorer</strong>
        <span>Scores, decisões e feedback</span>
      </a>
      <a class="quick-link" href="#/digests">
        <strong>Digests</strong>
        <span>Relatórios semanais e diários</span>
      </a>
      <a class="quick-link" href="#/sources">
        <strong>Fontes</strong>
        <span>RSS, GitHub e páginas web</span>
      </a>
    </nav>
  `;
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

const DIGEST_SECTIONS = [
  { key: "adopt", title: "Adotar", emoji: "✅", empty: "Nada para adotar nesta janela." },
  { key: "test", title: "Testar", emoji: "🔥", empty: "Nada em teste nesta janela." },
  { key: "monitor", title: "Monitorar", emoji: "👀", empty: "Nada em monitoramento." },
  { key: "ignore", title: "Ignorar", emoji: "❌", empty: "Nada para ignorar." },
];

function digestTypeLabel(t) {
  const map = {
    daily: "Diário",
    weekly: "Semanal",
    monthly: "Mensal",
    custom: "Personalizado",
  };
  return map[String(t || "").toLowerCase()] || t || "—";
}

function digestItemName(it) {
  return it.tool_name || it.title || "Sem título";
}

function renderReasonChips(reasons) {
  if (!reasons || reasons.length === 0) return "";
  return `<ul class="digest-reasons">${reasons
    .map((r) => `<li>${escapeHtml(r)}</li>`)
    .join("")}</ul>`;
}

function renderDigestItemCard(it) {
  const name = digestItemName(it);
  const score = scorePct(it.score);
  const category = it.category
    ? `<span class="digest-item-category">${escapeHtml(it.category)}</span>`
    : "";
  const risksBlock =
    it.risks && it.risks.length
      ? `<div class="digest-risks"><span class="digest-label">Riscos</span><ul>${it.risks
          .map((r) => `<li>${escapeHtml(r)}</li>`)
          .join("")}</ul></div>`
      : "";
  const nextBlock = it.next_step
    ? `<p class="digest-next"><span class="digest-label">Próximo passo</span> ${escapeHtml(it.next_step)}</p>`
    : "";
  const itemLink = it.extracted_item_id
    ? `<a class="digest-item-link" href="#/items/${it.extracted_item_id}">Ver item no radar</a>`
    : "";
  const extLink = it.url
    ? `<a class="digest-ext-link" href="${escapeHtml(it.url)}" target="_blank" rel="noopener">Fonte original</a>`
    : "";

  return `<article class="digest-item-card">
    <header class="digest-item-head">
      <div class="digest-item-badges">
        ${decisionBadge(it.decision)}
        <span class="digest-score-pill">${score}</span>
      </div>
      <h3 class="digest-item-title">${escapeHtml(name)}</h3>
      ${category}
    </header>
    <div class="digest-item-links">${itemLink}${extLink ? ` · ${extLink}` : ""}</div>
    ${renderReasonChips(it.reasons)}
    ${risksBlock}
    ${nextBlock}
  </article>`;
}

function renderDigestSection(section, items) {
  const list =
    items && items.length
      ? items.map((it) => renderDigestItemCard(it)).join("")
      : `<p class="muted digest-empty">${section.empty}</p>`;
  return `<section class="digest-section">
    <h2 class="digest-section-title">${section.emoji} ${section.title} <span class="digest-section-count">${items?.length || 0}</span></h2>
    <div class="digest-item-grid">${list}</div>
  </section>`;
}

function renderDigestStructured(digest) {
  const meta = digest.metadata_json || {};
  const buckets = meta.buckets || {};
  const summary = meta.summary || {};
  const periodStart = new Date(digest.period_start).toLocaleString("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
  });
  const periodEnd = new Date(digest.period_end).toLocaleString("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
  });
  const titleDate = new Date(digest.period_end).toLocaleDateString("pt-BR");
  const total = summary.total ?? 0;

  const summaryCards = [
    card("No relatório", total),
    card("Adotar", summary.adopt ?? buckets.adopt?.length ?? 0),
    card("Testar", summary.test ?? buckets.test?.length ?? 0),
    card("Monitorar", summary.monitor ?? buckets.monitor?.length ?? 0),
    card("Ignorar", summary.ignore ?? buckets.ignore?.length ?? 0),
  ].join("");

  const sections = DIGEST_SECTIONS.map((s) =>
    renderDigestSection(s, buckets[s.key] || []),
  ).join("");

  const rising = meta.rising_stars || [];
  const trending = meta.trending_adoption || [];
  const alerts = meta.sources_alert || [];
  const signalsSummary = meta.signals_summary || {};
  const highlights =
    rising.length || trending.length
      ? `<section class="digest-section digest-highlights">
    <h2 class="digest-section-title">✨ Destaques</h2>
    ${
      rising.length
        ? `<h3 class="digest-subtitle">Em ascensão</h3><ul class="digest-highlight-list">${rising
            .map(
              (h) =>
                `<li><strong>${escapeHtml(h.tool_name)}</strong> — ${scorePct(h.score)}${h.stars_delta_7d != null ? ` · Δ7d ${h.stars_delta_7d >= 0 ? "+" : ""}${fmtNum(h.stars_delta_7d)}` : ""}</li>`,
            )
            .join("")}</ul>`
        : ""
    }
    ${
      trending.length
        ? `<h3 class="digest-subtitle">Adoção</h3><ul class="digest-highlight-list">${trending
            .map(
              (h) =>
                `<li><strong>${escapeHtml(h.tool_name)}</strong> — ${escapeHtml(h.stars_tier || "")}${h.stars != null ? ` · ${fmtNum(h.stars)} ⭐` : ""}</li>`,
            )
            .join("")}</ul>`
        : ""
    }
    ${
      alerts.length
        ? `<p class="muted">Fontes em alerta: ${alerts.map((a) => escapeHtml(a.source_name)).join(", ")}</p>`
        : ""
    }
    ${
      signalsSummary.feedback_calibration_count
        ? `<p class="muted">${signalsSummary.feedback_calibration_count} score(s) calibrado(s) por feedback.</p>`
        : ""
    }
  </section>`
      : "";

  return `<div class="digest-report">
    <header class="digest-header">
      <p class="digest-back"><a href="#/digests">← Voltar</a></p>
      <h1 class="digest-title">AI Radar Digest — ${escapeHtml(titleDate)}</h1>
      <p class="digest-meta">${digestTypeLabel(digest.digest_type)} · ${escapeHtml(periodStart)} → ${escapeHtml(periodEnd)}</p>
    </header>
    <div class="cards digest-summary-cards">${summaryCards}</div>
    ${highlights}
    ${sections}
  </div>`;
}

async function renderDigest(id) {
  setNav("#/digests");
  const digest = await apiJson(`/digests/${id}`);
  const buckets = digest.metadata_json?.buckets;
  if (buckets) {
    $app.innerHTML = renderDigestStructured(digest);
    return;
  }
  const md = digest.markdown_content || "";
  $app.innerHTML = `<p><a href="#/digests">← Voltar</a></p><article class="digest-article digest-article--legacy">${renderMarkdown(md)}</article>`;
}

function explorerSearchFromForm() {
  const decision = document.getElementById("decision-filter")?.value || "";
  const starsTier = document.getElementById("stars-tier-filter")?.value || "";
  const velocityTier = document.getElementById("velocity-tier-filter")?.value || "";
  const sourceHealthTier =
    document.getElementById("source-health-filter")?.value || "";
  const sort = document.getElementById("sort-filter")?.value || "score_desc";
  const qualityWarn = document.getElementById("quality-warn-filter")?.checked;
  const semanticQ = document.getElementById("semantic-search")?.value?.trim() || "";
  const qs = new URLSearchParams();
  if (decision) qs.set("decision", decision);
  if (starsTier) qs.set("stars_tier", starsTier);
  if (velocityTier) qs.set("velocity_tier", velocityTier);
  if (sourceHealthTier) qs.set("source_health_tier", sourceHealthTier);
  if (sort && sort !== "score_desc") qs.set("sort", sort);
  if (qualityWarn) qs.set("quality_warn", "1");
  const noEmbed = document.getElementById("no-embedding-filter")?.checked;
  if (noEmbed) qs.set("has_embedding", "false");
  if (semanticQ) qs.set("q", semanticQ);
  location.search = qs.toString() ? `?${qs}` : "";
  render();
}

function bindExplorerFilters() {
  for (const id of [
    "decision-filter",
    "stars-tier-filter",
    "velocity-tier-filter",
    "source-health-filter",
    "sort-filter",
    "quality-warn-filter",
    "no-embedding-filter",
  ]) {
    document.getElementById(id)?.addEventListener("change", explorerSearchFromForm);
  }
  const searchEl = document.getElementById("semantic-search");
  if (searchEl) {
    searchEl.addEventListener("input", () => {
      clearTimeout(semanticSearchTimer);
      semanticSearchTimer = setTimeout(explorerSearchFromForm, 400);
    });
    searchEl.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        clearTimeout(semanticSearchTimer);
        explorerSearchFromForm();
      }
    });
  }
}

function explorerSemanticSearchBar(query) {
  return `<label class="filter-row filter-row--search">Busca semântica
    <input type="search" id="semantic-search" placeholder="Ex.: agente de código self-hosted no cluster…" value="${escapeHtml(query)}" autocomplete="off" />
  </label>`;
}

function explorerFilterControls({
  decision,
  starsTier,
  velocityTier,
  sourceHealthTier,
  sort,
  qualityWarn,
  noEmbedding,
  semanticQ,
  filtersDisabled = false,
}) {
  const disabled = filtersDisabled ? " disabled" : "";
  const decisionOpts = ["", "adopt", "test", "monitor", "ignore"]
    .map(
      (d) =>
        `<option value="${d}" ${d === decision ? "selected" : ""}>${d || "todas decisões"}</option>`,
    )
    .join("");
  const tierOpts = ["", "viral", "popular", "growing", "niche"]
    .map(
      (t) =>
        `<option value="${t}" ${t === starsTier ? "selected" : ""}>${t || "qualquer adoção"}</option>`,
    )
    .join("");
  const velocityOpts = ["", "spike", "growing", "flat", "declining"]
    .map(
      (t) =>
        `<option value="${t}" ${t === velocityTier ? "selected" : ""}>${t ? VELOCITY_TIER_PT[t] || t : "qualquer tendência"}</option>`,
    )
    .join("");
  const healthOpts = ["", "healthy", "degraded", "noisy"]
    .map(
      (t) =>
        `<option value="${t}" ${t === sourceHealthTier ? "selected" : ""}>${t || "saúde fonte"}</option>`,
    )
    .join("");
  const sortOpts = [
    ["score_desc", "Score ↓"],
    ["adoption_desc", "Adoção ↓"],
    ["scored_at_desc", "Mais recentes"],
  ]
    .map(
      ([v, label]) =>
        `<option value="${v}" ${v === sort ? "selected" : ""}>${label}</option>`,
    )
    .join("");
  return `<div class="explorer-filters">
    ${explorerSemanticSearchBar(semanticQ)}
    <label class="filter-row">Decisão <select id="decision-filter"${disabled}>${decisionOpts}</select></label>
    <label class="filter-row">Stars tier <select id="stars-tier-filter"${disabled}>${tierOpts}</select></label>
    <label class="filter-row">Tendência <select id="velocity-tier-filter"${disabled}>${velocityOpts}</select></label>
    <label class="filter-row">Saúde fonte <select id="source-health-filter"${disabled}>${healthOpts}</select></label>
    <label class="filter-row">Ordenar <select id="sort-filter"${disabled}>${sortOpts}</select></label>
    <label class="filter-row filter-row--check"><input type="checkbox" id="quality-warn-filter" ${qualityWarn ? "checked" : ""}${disabled} /> Só quality warn</label>
    <label class="filter-row filter-row--check"><input type="checkbox" id="no-embedding-filter" ${noEmbedding ? "checked" : ""}${disabled} /> Só sem vetor</label>
  </div>`;
}

async function renderItems() {
  setNav("#/items");
  const params = new URLSearchParams(location.search);
  const decision = params.get("decision") || "";
  const starsTier = params.get("stars_tier") || "";
  const velocityTier = params.get("velocity_tier") || "";
  const sourceHealthTier = params.get("source_health_tier") || "";
  const sort = params.get("sort") || "score_desc";
  const qualityWarn = params.get("quality_warn") === "1";
  const noEmbedding = params.get("has_embedding") === "false";
  const semanticQ = (params.get("q") || "").trim();

  const filterArgs = {
    decision,
    starsTier,
    velocityTier,
    sourceHealthTier,
    sort,
    qualityWarn,
    noEmbedding,
    semanticQ,
  };
  const filters = explorerFilterControls({
    ...filterArgs,
    filtersDisabled: Boolean(semanticQ),
  });

  const header = `<header class="explorer-header">
    <h1 class="section-title">Explorer</h1>
    <p class="muted">Ferramentas scored com sinais de adoção e decisão.</p>
  </header>`;

  if (semanticQ) {
    const searchQs = new URLSearchParams({ q: semanticQ, limit: "50" });
    const searchRes = await apiJson(`/search?${searchQs}`);
    const modeLabel =
      searchRes.mode === "semantic"
        ? "Busca semântica (embeddings)"
        : "Busca lexical — embeddings desabilitados ou indisponíveis";
    const modeHint =
      searchRes.mode === "lexical"
        ? `<p class="search-mode-hint muted">Modo lexical: ative <code>EMBEDDINGS_ENABLED</code> e rode o pipeline de embed para busca vetorial.</p>`
        : "";

    if (!searchRes.items || searchRes.items.length === 0) {
      let semanticEmptyHint = "";
      if (searchRes.mode === "semantic") {
        const stats = await apiJson("/stats").catch(() => ({}));
        const cov = stats.embeddings?.coverage_pct ?? 0;
        const pending = stats.embeddings?.embeddings_pending ?? 0;
        if (cov < 30 && pending > 0) {
          semanticEmptyHint = `<p class="search-empty-hint">Cobertura de embeddings baixa (${Math.round(cov)}%, ${fmtNum(pending)} na fila). Rode o backfill de embed para melhorar a busca semântica.</p>`;
        } else {
          semanticEmptyHint =
            '<p class="search-empty-hint">Nenhum match semântico para essa consulta. Tente termos do resumo/categoria da ferramenta ou palavras mais genéricas.</p>';
        }
      }
      $app.innerHTML = `${header}
        ${filters}
        <p class="muted search-empty">Nenhum resultado para “${escapeHtml(searchRes.query || semanticQ)}”.</p>
        <p class="muted">${escapeHtml(modeLabel)}</p>
        ${modeHint}
        ${semanticEmptyHint}`;
      bindExplorerFilters();
      return;
    }

    const rows = searchRes.items
      .map((hit) => {
        const it = hit.item || hit;
        const sim = hit.similarity;
        const name = it.tool_name || it.summary?.slice(0, 48) || it.extracted_item_id;
        return `<tr>
          <td><span class="badge badge-similarity" title="similaridade">${similarityPct(sim)}</span></td>
          <td>${decisionBadge(it.decision)}</td>
          <td>${scorePct(it.score)}</td>
          <td class="signal-cell">${signalBadges(it.adoption, it.quality_warn)}</td>
          <td>${escapeHtml(it.category || "—")}</td>
          <td><a href="#/items/${it.extracted_item_id}">${escapeHtml(name)}</a></td>
        </tr>`;
      })
      .join("");

    $app.innerHTML = `${header}
      ${filters}
      <p class="muted">${searchRes.count} resultado(s) · ${escapeHtml(modeLabel)}</p>
      ${modeHint}
      <div class="table-wrap"><table class="explorer-table">
        <thead><tr><th>Match</th><th>Decisão</th><th>Score</th><th>Sinais</th><th>Categoria</th><th>Ferramenta</th></tr></thead>
        <tbody>${rows}</tbody>
      </table></div>`;
    bindExplorerFilters();
    return;
  }

  const qs = new URLSearchParams({ limit: "50", sort });
  if (decision) qs.set("decision", decision);
  if (starsTier) qs.set("stars_tier", starsTier);
  if (velocityTier) qs.set("velocity_tier", velocityTier);
  if (sourceHealthTier) qs.set("source_health_tier", sourceHealthTier);
  if (qualityWarn) qs.set("quality_warn", "true");
  if (noEmbedding) qs.set("has_embedding", "false");

  const data = await apiJson(`/items?${qs}`);

  if (!data.items || data.items.length === 0) {
    $app.innerHTML = `${header}
    ${filters}
    <p class="muted">Nenhum item com esses filtros.</p>`;
    bindExplorerFilters();
    return;
  }

  const rows = data.items
    .map((it) => {
      const name = it.tool_name || it.summary?.slice(0, 48) || it.extracted_item_id;
      return `<tr>
        <td>${decisionBadge(it.decision)}</td>
        <td>${scorePct(it.score)}</td>
        <td class="signal-cell">${signalBadges(it.adoption, it.quality_warn)}${embeddingBadge(it.has_embedding)}</td>
        <td>${escapeHtml(it.category || "—")}</td>
        <td><a href="#/items/${it.extracted_item_id}">${escapeHtml(name)}</a></td>
        <td class="muted">${new Date(it.scored_at).toLocaleString("pt-BR")}</td>
      </tr>`;
    })
    .join("");

  $app.innerHTML = `${header}
    <p class="muted">${data.count} de ${data.total} itens scored</p>
    ${filters}
    <div class="table-wrap"><table class="explorer-table">
      <thead><tr><th>Decisão</th><th>Score</th><th>Sinais</th><th>Categoria</th><th>Ferramenta</th><th>Scored em</th></tr></thead>
      <tbody>${rows}</tbody>
    </table></div>`;

  bindExplorerFilters();
}

async function renderItem(id) {
  setNav("#/items");
  const [data, related] = await Promise.all([
    apiJson(`/items/${id}`),
    apiJson(`/items/${id}/related?limit=8&same_category=true`).catch(() => ({
      has_embedding: false,
      items: [],
      count: 0,
      same_category: true,
    })),
  ]);
  const ex = data.extracted;
  const raw = data.raw || {};
  const sc = data.latest_score;
  const title = ex.tool_name || raw.title || ex.summary?.slice(0, 80) || id;
  const points = scorePoints(sc.metadata_json);

  const reasons = jsonStringList(sc.reasons_json).map(humanizeReason);
  const risks = jsonStringList(sc.risks_json);
  const nextStep = sc.next_step && !isGenericNextStep(sc.next_step) ? sc.next_step : null;

  const attrs = itemDl([
    ["Categoria", escapeHtml(ex.category || "—")],
    ["Extractor", escapeHtml(ex.extractor || "—")],
    ["Versão extract", `v${ex.version}`],
    ["Maturidade", escapeHtml(fmtLabel(MATURITY_PT, ex.maturity))],
    ["Risco (extract)", escapeHtml(fmtLabel(RISK_PT, ex.risk_level))],
    ["Licença", escapeHtml(ex.license || "—")],
    ["Self-host", escapeHtml(fmtBool(ex.self_hosted))],
    ["SaaS only", escapeHtml(fmtBool(ex.saas_only))],
    ["Scoring", escapeHtml(sc.scoring_version || "—")],
    ["Pontos", points != null ? `${points}/100` : "—"],
    ["Status bruto", escapeHtml(raw.status || "—")],
    ["Coletado em", escapeHtml(fmtDate(raw.collected_at))],
    ["Publicado em", escapeHtml(fmtDate(raw.published_at))],
    ["Extract em", escapeHtml(fmtDate(ex.created_at))],
    ["Scored em", escapeHtml(fmtDate(sc.created_at))],
  ]);

  const signalsPanel = renderItemSignalsPanel(ex, sc);
  const relatedPanel = renderRelatedPanel(related, id);
  const compareLink = ex.category
    ? `<a class="btn btn-ghost" href="#/compare?category=${encodeURIComponent(ex.category)}">Comparar categoria</a>`
    : "";

  const reasonsBlock =
    reasons.length > 0
      ? `<ul class="digest-reasons item-reasons">${reasons
          .map((r) => `<li>${escapeHtml(r)}</li>`)
          .join("")}</ul>`
      : `<p class="muted">Nenhum motivo registrado.</p>`;

  const risksBlock =
    risks.length > 0
      ? `<ul class="item-risks-list">${risks
          .map((r) => `<li>${escapeHtml(r)}</li>`)
          .join("")}</ul>`
      : "";

  const rawPreview =
    raw.raw_content && raw.raw_content.length > 0
      ? `<details class="item-raw-details">
          <summary>Conteúdo coletado (${raw.raw_content.length.toLocaleString("pt-BR")} caracteres)</summary>
          <pre class="item-raw-pre">${escapeHtml(raw.raw_content.slice(0, 8000))}${
            raw.raw_content.length > 8000 ? "\n\n… (truncado)" : ""
          }</pre>
        </details>`
      : "";

  const history =
    data.scores?.length > 1
      ? itemSection(
          "Histórico de scores",
          `<ul class="score-history">${data.scores
            .map((s) => {
              const pts = scorePoints(s.metadata_json);
              const ptsLabel = pts != null ? ` · ${pts}/100` : "";
              return `<li>${decisionBadge(s.decision)} ${scorePct(s.score)}${ptsLabel} — ${escapeHtml(s.scoring_version)} <span class="muted">${fmtDate(s.created_at)}</span></li>`;
            })
            .join("")}</ul>`,
        )
      : "";

  const sourceLink = raw.url
    ? `<a href="${escapeHtml(raw.url)}" target="_blank" rel="noopener" class="item-source-link">Abrir fonte original</a>`
    : "";


  const feedbackTypes = [
    "useful",
    "irrelevant",
    "duplicate",
    "low_quality",
    "wrong_category",
    "adopted",
    "tested",
    "monitoring",
    "rejected",
  ];
  const feedbackHistory =
    data.feedbacks && data.feedbacks.length
      ? `<ul class="item-feedback-history">${data.feedbacks
          .map(
            (f) =>
              `<li><strong>${escapeHtml(f.feedback_type)}</strong>${f.notes ? ` — ${escapeHtml(f.notes)}` : ""} <span class="muted">${fmtDate(f.created_at)}</span></li>`,
          )
          .join("")}</ul>`
      : `<p class="muted">Nenhum feedback ainda.</p>`;
  const feedbackForm = `<form class="item-feedback-form" id="feedback-form">
    <label class="filter-row">Tipo
      <select id="feedback-type" required>${feedbackTypes
        .map((t) => `<option value="${t}">${t}</option>`)
        .join("")}</select>
    </label>
    <label class="filter-row">Notas
      <textarea id="feedback-notes" rows="2" placeholder="opcional"></textarea>
    </label>
    <button type="submit" class="btn">Enviar feedback</button>
  </form>`;

  $app.innerHTML = `<div class="item-detail">
    <p class="item-back"><a href="#/items">← Voltar</a></p>
    <header class="item-hero">
      <h1 class="item-title">${escapeHtml(title)}</h1>
      <div class="item-hero-meta">
        ${decisionBadge(sc.decision)}
        <span class="digest-score-pill">${scorePct(sc.score)}</span>
        ${points != null ? `<span class="item-points muted">${points}/100 pts</span>` : ""}
      </div>
      ${sourceLink}
      ${compareLink ? `<div class="item-hero-actions">${compareLink}</div>` : ""}
    </header>
    ${itemTextBlock("Resumo", ex.summary)}
    ${signalsPanel}
    ${relatedPanel}
    ${itemSection("Atributos", attrs)}
    ${itemTextBlock("Problema / caso de uso", ex.problem_solved)}
    ${itemTextBlock("Encaixe de stack", ex.stack_fit)}
    ${itemSection("Por que este score?", reasonsBlock)}
    ${risksBlock ? itemSection("Riscos sinalizados", risksBlock) : ""}
    ${
      nextStep
        ? itemSection("Próximo passo", `<p class="item-next">${escapeHtml(nextStep)}</p>`)
        : `<p class="muted item-next-hint">Próximo passo padrão do motor — valide manualmente conforme a categoria.</p>`
    }
    ${itemSection("Origem", rawPreview)}
    ${itemSection("Seu feedback", `${feedbackHistory}${feedbackForm}`)}
    <div class="actions">
      <button type="button" class="btn" id="reprocess-score">Re-score</button>
    </div>
    ${history}
    <p id="reprocess-status" class="muted" aria-live="polite"></p>
  </div>`;

  bindRelatedPanel(id);

  document.getElementById("feedback-form")?.addEventListener("submit", async (e) => {
    e.preventDefault();
    const status = document.getElementById("reprocess-status");
    const feedbackType = document.getElementById("feedback-type")?.value;
    const notes = document.getElementById("feedback-notes")?.value?.trim() || null;
    status.textContent = "Enviando feedback…";
    status.className = "muted";
    try {
      await apiPost(`/items/${id}/feedback`, {
        feedback_type: feedbackType,
        notes,
      });
      status.textContent = "Feedback registrado.";
      await renderItem(id);
    } catch (err) {
      status.textContent = err.message;
      status.className = "error";
    }
  });

  document.getElementById("reprocess-score")?.addEventListener("click", async () => {
    const status = document.getElementById("reprocess-status");
    if (!confirm("Re-executar scoring determinístico para este item?")) return;
    status.textContent = "Executando…";
    try {
      await apiPost(`/items/${id}/reprocess`, { stage: "score" });
      status.textContent = "Concluído. Recarregando…";
      await renderItem(id);
    } catch (err) {
      status.textContent = err.message;
      status.className = "error";
    }
  });
}


function sourceHealthBadge(tier) {
  if (!tier) return '<span class="muted">—</span>';
  const label = { healthy: "Saudável", degraded: "Degradada", noisy: "Ruidosa", unknown: "?" }[
    tier
  ] || tier;
  return `<span class="badge badge-health badge-health-${escapeHtml(tier)}">${escapeHtml(label)}</span>`;
}

function parseSemanticDupThreshold() {
  const raw = new URLSearchParams(location.search).get("threshold");
  const n = raw != null ? Number.parseFloat(raw) : 0.92;
  if (Number.isNaN(n)) {
    return 0.92;
  }
  return Math.min(0.999, Math.max(0.5, n));
}

function bindSemanticDupControls(onApply) {
  const form = document.getElementById("semantic-dup-form");
  const range = document.getElementById("semantic-dup-threshold");
  const out = document.getElementById("semantic-dup-threshold-out");
  if (!form || !range || !out) {
    return;
  }
  range.addEventListener("input", () => {
    out.textContent = `${range.value}%`;
  });
  form.addEventListener("submit", (e) => {
    e.preventDefault();
    const thr = Number(range.value) / 100;
    const qs = new URLSearchParams(location.search);
    qs.set("threshold", String(thr));
    location.search = `?${qs}`;
    onApply(thr);
  });
}

async function renderReportsSemanticDuplicates() {
  setNav("#/reports/semantic-duplicates");
  const threshold = parseSemanticDupThreshold();

  const load = async (thr) => {
  const data = await apiJson(
    `/reports/semantic-duplicates?threshold=${encodeURIComponent(thr)}&limit=50`,
  );
    const scanned = data.scanned ?? 0;
    const thrPct = Math.round((data.threshold ?? thr) * 100);
    const controls = `<form class="semantic-dup-controls" id="semantic-dup-form">
      <label class="semantic-dup-threshold-label">Threshold de similaridade
        <span class="semantic-dup-threshold-row">
          <input type="range" id="semantic-dup-threshold" min="50" max="99" value="${thrPct}" />
          <output id="semantic-dup-threshold-out">${thrPct}%</output>
        </span>
      </label>
      <button type="submit" class="btn btn-ghost">Atualizar relatório</button>
    </form>`;

    let emptyBlock = "";
    if (scanned < 10) {
      emptyBlock = `<div class="search-empty-hint">
        Apenas <strong>${fmtNum(scanned)}</strong> embeddings no pool (mínimo ~10 para análise útil).
        Veja cobertura na <a href="#/">home</a> e rode o backfill de embed (CronJob <code>ai-radar-embed</code> ou README § Embedding backfill).
      </div>`;
    } else if (!data.pairs?.length) {
      emptyBlock = `<p class="muted search-empty">Nenhum par acima de ${thrPct}% entre ${fmtNum(scanned)} embeddings. Baixe o threshold ou aguarde mais itens embedados.</p>`;
    }

    const rows = (data.pairs || [])
      .map((p) => {
        const nameA = p.tool_name_a || p.extracted_item_id_a;
        const nameB = p.tool_name_b || p.extracted_item_id_b;
        return `<tr>
          <td><span class="badge badge-similarity">${similarityPct(p.similarity)}</span></td>
          <td><a href="#/items/${p.extracted_item_id_a}">${escapeHtml(nameA)}</a></td>
          <td>${scorePct(p.score_a ?? 0)}</td>
          <td class="muted">${escapeHtml(p.category_a || "—")}</td>
          <td><a href="#/items/${p.extracted_item_id_b}">${escapeHtml(nameB)}</a></td>
          <td>${scorePct(p.score_b ?? 0)}</td>
          <td class="muted">${escapeHtml(p.category_b || "—")}</td>
          <td class="semantic-dup-actions">
            <a class="btn btn-ghost btn-sm" href="#/items/${p.extracted_item_id_a}">A</a>
            <a class="btn btn-ghost btn-sm" href="#/items/${p.extracted_item_id_b}">B</a>
          </td>
        </tr>`;
      })
      .join("");

    const table =
      data.pairs?.length > 0
        ? `<div class="table-wrap"><table class="explorer-table semantic-dup-table">
        <thead><tr>
          <th>Sim.</th><th>Item A</th><th>Score A</th><th>Cat. A</th>
          <th>Item B</th><th>Score B</th><th>Cat. B</th><th></th>
        </tr></thead>
        <tbody>${rows}</tbody></table></div>`
        : "";

    $app.innerHTML = `<header class="explorer-header">
      <h1 class="section-title">Duplicatas semânticas</h1>
      <p class="muted">${data.count} pares · ${fmtNum(scanned)} embeddings analisados · somente leitura</p>
      <p class="muted"><a href="#/reports/duplicates">Duplicatas URL (tool_key)</a> · revisão manual, sem auto-merge</p>
    </header>
    ${controls}
    ${emptyBlock}
    ${table}`;
    bindSemanticDupControls(load);
  };

  await load(threshold);
}

async function renderReportsDuplicates() {
  setNav("#/reports/duplicates");
  const data = await apiJson("/reports/duplicates?limit=50");
  const rows = (data.clusters || [])
    .map(
      (c) => `<tr>
        <td><code>${escapeHtml(c.tool_key || "—")}</code></td>
        <td>${c.active_count} ativos · ${c.duplicate_count} dup</td>
        <td class="muted">${escapeHtml((c.sources || []).join(", "))}</td>
      </tr>`,
    )
    .join("");
  $app.innerHTML = `<header class="explorer-header">
    <h1 class="section-title">Duplicatas cross-fonte</h1>
    <p class="muted">${data.count} clusters · <a href="#/reports/semantic-duplicates">Dup. semântica</a> · <a href="#/reports/divergence">Divergência</a></p>
  </header>
  <div class="table-wrap"><table><thead><tr><th>tool_key</th><th>Contagem</th><th>Fontes</th></tr></thead>
  <tbody>${rows || '<tr><td colspan="3" class="muted">Nenhum cluster</td></tr>'}</tbody></table></div>`;
}

async function renderReportsDivergence() {
  setNav("#/reports/divergence");
  const data = await apiJson("/reports/divergence?limit=50");
  const rows = (data.items || [])
    .map(
      (d) => `<tr>
        <td><a href="#/items/${d.extracted_item_id}">${escapeHtml(d.tool_name || d.extracted_item_id)}</a></td>
        <td>${escapeHtml(d.feedback?.feedback_type || "—")}</td>
        <td>${decisionBadge(d.decision)}</td>
        <td>${scorePct(d.score)}</td>
      </tr>`,
    )
    .join("");
  $app.innerHTML = `<header class="explorer-header">
    <h1 class="section-title">Divergência feedback × scorer</h1>
    <p class="muted">${data.count} linhas · <a href="#/reports/duplicates">Duplicatas</a></p>
  </header>
  <div class="table-wrap"><table><thead><tr><th>Item</th><th>Feedback</th><th>Decisão</th><th>Score</th></tr></thead>
  <tbody>${rows || '<tr><td colspan="4" class="muted">Nenhuma divergência</td></tr>'}</tbody></table></div>`;
}

async function renderCompare(prefillCategory = "") {
  setNav("#/compare");
  const recent = await apiJson("/comparisons?limit=8").catch(() => ({ items: [] }));
  const recentRows = (recent.items || [])
    .map(
      (c) =>
        `<tr><td>${escapeHtml(c.category)}</td><td>${c.top_n}</td><td>${fmtDate(c.generated_at)}</td></tr>`,
    )
    .join("");
  $app.innerHTML = `<header class="explorer-header">
    <h1 class="section-title">Comparator</h1>
    <p class="muted">Matriz Markdown por categoria (T-168 / T-237).</p>
  </header>
  <form id="compare-form" class="compare-form">
    <label>Categoria <input name="category" type="text" placeholder="ex: LLM observability" required value="${escapeHtml(prefillCategory)}" /></label>
    <label>Top N <input name="top_n" type="number" min="1" max="50" value="5" /></label>
    <button type="submit" class="btn-primary">Gerar matriz</button>
  </form>
  <div id="compare-status" class="muted"></div>
  <article id="compare-output" class="digest-report" style="display:none"></article>
  <h2 class="section-title">Comparações recentes</h2>
  <div class="table-wrap"><table><thead><tr><th>Categoria</th><th>Top</th><th>Gerado</th></tr></thead>
  <tbody>${recentRows || '<tr><td colspan="3" class="muted">Nenhuma ainda</td></tr>'}</tbody></table></div>`;

  const form = document.getElementById("compare-form");
  const status = document.getElementById("compare-status");
  const output = document.getElementById("compare-output");
  form?.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const fd = new FormData(form);
    const category = String(fd.get("category") || "").trim();
    const top_n = Number(fd.get("top_n") || 5);
    status.textContent = "Gerando…";
    output.style.display = "none";
    try {
      const res = await apiPost("/compare", { category, top_n });
      output.innerHTML = renderMarkdown(res.markdown || "");
      output.style.display = "block";
      status.textContent = `Salvo (${res.id}) — ${escapeHtml(res.category)}`;
    } catch (err) {
      status.textContent = err.message;
      status.className = "error";
    }
  });
}

async function renderSources() {
  setNav("#/sources");
  const [data, healthData] = await Promise.all([
    apiJson("/sources"),
    apiJson("/sources/health").catch(() => ({ items: [] })),
  ]);
  const healthById = new Map(
    (healthData.items || []).map((h) => [h.source_id, h]),
  );
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
      const h = healthById.get(s.id);
      const health = sourceHealthBadge(h?.tier);
      const failPct =
        h && h.raw_total > 0
          ? `${Math.round((100 * h.raw_failed) / h.raw_total)}%`
          : "—";
      return `<tr>
        <td>${escapeHtml(s.name)}</td>
        <td><code>${escapeHtml(s.source_type)}</code></td>
        <td>${health}</td>
        <td>${failPct}</td>
        <td>${enabled}</td>
        <td>${s.poll_interval_minutes} min</td>
        <td><a href="${escapeHtml(s.url)}" target="_blank" rel="noopener">link</a></td>
      </tr>`;
    })
    .join("");
  $app.innerHTML = `<h1 class="section-title">Fontes</h1><p class="muted">Saúde agregada por taxa de falha e duplicatas (T-238).</p><div class="table-wrap"><table><thead><tr><th>Nome</th><th>Tipo</th><th>Saúde</th><th>Falhas</th><th>Ativa</th><th>Poll</th><th>URL</th></tr></thead><tbody>${rows}</tbody></table></div>`;
}

async function render() {
  const route = parseRoute();
  $app.innerHTML = '<p class="loading">Carregando…</p>';
  try {
    if (route.page === "home") await renderHome();
    else if (route.page === "digests") await renderDigests();
    else if (route.page === "digest") await renderDigest(route.id);
    else if (route.page === "items") await renderItems();
    else if (route.page === "item") await renderItem(route.id);
    else if (route.page === "sources") await renderSources();
    else if (route.page === "reports-duplicates") await renderReportsDuplicates();
    else if (route.page === "reports-semantic-duplicates")
      await renderReportsSemanticDuplicates();
    else if (route.page === "reports-divergence") await renderReportsDivergence();
    else if (route.page === "compare") await renderCompare(route.category || "");
  } catch (err) {
    $app.innerHTML = `<p class="error">${escapeHtml(err.message)}</p>`;
  }
}

window.addEventListener("hashchange", render);
render();
