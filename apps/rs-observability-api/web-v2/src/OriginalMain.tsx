export function OriginalMain() {
  return (
    <main>
<section class="shell">
        <header class="masthead">
          <div class="brand">
            <span class="eyebrow">Operations-first observability</span>
            <h1>Cluster pulse for triage, not just reporting.</h1>
            <p class="subhead">
              Live Kubernetes health and Prometheus pressure stay in the foreground.
              Catalog and deploy context remain available, but secondary.
            </p>
            <div class="meta-row">
              <span class="pill" id="generated-at">Loading snapshot metadata...</span>
              <span class="pill" id="live-refresh">Connecting to live cluster API...</span>
              <span class="pill" id="metrics-refresh">Connecting to Prometheus...</span>
            </div>
          </div>

          <aside class="command-card" id="signal-card" data-tone="healthy">
            <div class="command-top">
              <div class="signal-badge">
                <span class="live-dot"></span>
                <span id="live-mode">Connecting live watch</span>
              </div>
              <span id="auto-refresh">Auto-refresh pending</span>
            </div>
            <div class="command-score" id="health-score">--</div>
            <p class="command-copy" id="health-copy">Waiting for the first cluster response.</p>
            <div class="next-step">
              <strong>Next action</strong>
              <span id="next-action">Waiting for the first operator recommendation.</span>
            </div>
          </aside>
        </header>

        <section class="operator-grid" id="signal-grid">
          <div class="signal-mini">
            <strong>--</strong>
            <span>Active incidents</span>
          </div>
        </section>

        <section class="metric-band">
          <div class="section-head">
            <div>
              <div class="section-kicker">Core load</div>
              <div class="section-title">Cluster Pressure</div>
              <p>Prometheus-backed CPU, memory and restart pressure over the current dashboard window.</p>
            </div>
            <div class="section-tags">
              <span class="panel-tag" id="metrics-section-tag">Waiting for metrics</span>
            </div>
          </div>
          <div class="metric-grid" id="cluster-metrics">
            <article class="metric-card">
              <div class="metric-label">Loading metrics...</div>
            </article>
          </div>
        </section>

        <section class="priority-grid">
          <section class="panel priority-panel">
            <div class="section-head">
              <div>
                <div class="section-title">Immediate Action</div>
                <p>Live kube incidents first. This block should explain why an operator needs to care now.</p>
              </div>
              <div class="section-tags">
                <span class="panel-tag" id="ops-section-tag">Waiting for live data</span>
              </div>
            </div>
            <div class="incident-list" id="incident-list">
              <div class="incident-item">
                <div class="incident-body">
                  <strong>Waiting for cluster events</strong>
                  <span>No live data yet.</span>
                </div>
              </div>
            </div>
          </section>

          <section class="panel priority-panel">
            <div class="section-head">
              <div>
                <div class="section-title">Restart Debt</div>
                <p>Prometheus-ranked restart hotspots over the last hour, rounded to discrete events.</p>
              </div>
              <div class="section-tags">
                <span class="panel-tag" id="restart-section-tag">Waiting for Prometheus</span>
              </div>
            </div>
            <div class="hotspot-list" id="restart-list">
              <div class="hotspot-item">
                <div class="hotspot-body">
                  <strong>Waiting for Prometheus</strong>
                  <span>No hotspot data yet.</span>
                </div>
              </div>
            </div>
          </section>
        </section>

        <div class="content-grid">
          <section class="main-stack">
            <section class="panel">
              <div class="section-head">
                <div>
                  <div class="section-title">Critical Services</div>
                  <p>Live kube health, readiness, restart count and serving routes for the tracked surface.</p>
                </div>
                <div class="section-tags">
                  <span class="panel-tag" id="services-section-tag">Waiting for live data</span>
                </div>
              </div>
              <div class="service-grid" id="service-grid">
                <article class="service-card"><p class="empty">Loading live service board...</p></article>
              </div>
            </section>

            <section class="panel">
              <div class="section-head">
                <div>
                  <div class="section-title">Service Telemetry</div>
                  <p>Prometheus time-series stay close to service health so the board reads like an action surface.</p>
                </div>
                <div class="section-tags">
                  <span class="panel-tag" id="telemetry-section-tag">Waiting for metrics</span>
                </div>
              </div>
              <div class="telemetry-grid" id="telemetry-grid">
                <article class="telemetry-card"><p class="empty">Waiting for Prometheus time-series...</p></article>
              </div>
            </section>
          </section>

          <aside class="rail-stack">
            <section class="panel">
              <div class="section-head">
                <div>
                  <div class="section-title">Runtime Summary</div>
                  <p>Operational rollup only. This panel should not depend on snapshot interpretation.</p>
                </div>
                <div class="section-tags">
                  <span class="panel-tag" id="summary-section-tag">Waiting for live data</span>
                </div>
              </div>
              <div class="summary-grid" id="summary-grid">
                <article class="summary-card">
                  <strong>-</strong>
                  <span>Waiting for summary</span>
                </article>
              </div>
            </section>

            <section class="panel">
              <div class="section-head">
                <div>
                  <div class="section-title">Catalog Snapshot</div>
                  <p>Snapshot-derived counts stay visible, but secondary to live operations.</p>
                </div>
                <div class="section-tags">
                  <span class="panel-tag" id="catalog-summary-tag">Waiting for snapshot</span>
                </div>
              </div>
              <div class="catalog-summary-grid" id="catalog-summary-grid">
                <article class="summary-card">
                  <strong>-</strong>
                  <span>Waiting for snapshot</span>
                </article>
              </div>
            </section>

            <section class="panel">
              <div class="section-head">
                <div>
                  <div class="section-title">Language Mix</div>
                  <p>Repo composition is still useful context when deciding where to intervene.</p>
                </div>
              </div>
              <div class="language-bars" id="language-bars">
                <div class="language-row">
                  <div class="language-head"><span>Loading</span><strong>--</strong></div>
                  <div class="language-track"><div class="language-fill" style={{'width': '18%'}}></div></div>
                </div>
              </div>
            </section>
          </aside>
        </div>

        <section class="catalog-zone">
          <div class="catalog-shell">
            <div class="catalog-head">
              <div>
                <div class="section-kicker">Secondary surface</div>
                <h2>Catalog and deploy context</h2>
              </div>
              <div>
                <p>
                  Deploy paths, artifact bundle and snapshot inventory remain available without stealing
                  first-fold attention from operations.
                </p>
                <div class="section-tags">
                  <span class="panel-tag" id="catalog-zone-tag">Waiting for snapshot</span>
                  <span class="panel-tag route-tag">Routes: /api/live/overview, /api/catalog, /api/reports</span>
                </div>
              </div>
            </div>

            <div class="catalog-layout">
              <div class="catalog-main">
                <section>
                  <div class="section-head">
                    <div>
                      <div class="section-title">Deployable Surface</div>
                      <p id="deployable-meta">Waiting for catalog classification...</p>
                    </div>
                  </div>
                  <div class="table-shell">
                    <table>
                      <thead>
                        <tr>
                          <th>App</th>
                          <th>Stack</th>
                          <th>Deploy Path</th>
                          <th>Readiness</th>
                        </tr>
                      </thead>
                      <tbody id="apps-body">
                        <tr><td colSpan={4}>Loading catalog...</td></tr>
                      </tbody>
                    </table>
                  </div>
                </section>
              </div>

              <aside class="catalog-side">
                <section>
                  <div class="section-head">
                    <div>
                      <div class="section-title">Artifact Library</div>
                      <p>Static report bundle served from the image snapshot.</p>
                    </div>
                  </div>
                  <div class="artifact-list" id="artifact-list">
                    <div class="artifact"><p>Loading artifact index...</p></div>
                  </div>
                </section>
              </aside>
            </div>
          </div>
        </section>
      </section>

      <div id="error-box"></div>
    </main>
  );
}
