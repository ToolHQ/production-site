import './index.css';
import { useEffect, useState } from 'preact/hooks';
import { useLiveOverview } from './hooks/useLiveOverview';
import { useSnapshot } from './hooks/useSnapshot';
import { useTheme } from './hooks/useTheme';
import { useCorootAlerts } from './hooks/useCorootAlerts';
import { useCorootIncidents } from './hooks/useCorootIncidents';
import { useStorageHealth } from './hooks/useStorageHealth';
import { useCronJobs } from './hooks/useCronJobs';
import { useIngresses } from './hooks/useIngresses';
import { useCertificates } from './hooks/useCertificates';
import { useWorkloads } from './hooks/useWorkloads';
import { useNamespaces } from './hooks/useNamespaces';

import { DashboardHeader } from './components/DashboardHeader';
import { SignalCard, SignalGrid } from './components/SignalCard';
import { NodesPanel } from './components/NodesPanel';
import { ClusterMetrics } from './components/ClusterMetrics';
import { IncidentList, RestartHotspots } from './components/IncidentList';
import { ServiceGrid } from './components/ServiceCard';
import { TelemetryGrid } from './components/TelemetryCard';
import { RuntimeSummary, CatalogSummary } from './components/SummaryGrid';
import { LanguageBars } from './components/LanguageBars';
import { CatalogTable, ArtifactList } from './components/CatalogTable';
import { CorootAlertsPanel } from './components/CorootAlertsPanel';
import { CorootIncidentsPanel } from './components/CorootIncidentsPanel';
import { StoragePanel } from './components/StoragePanel';
import { CronJobPanel } from './components/CronJobPanel';
import { IngressPanel } from './components/IngressPanel';
import { CertExpiryPanel } from './components/CertExpiryPanel';
import { WorkloadPanel } from './components/WorkloadPanel';
import { NamespacePanel } from './components/NamespacePanel';
import { DnorTopNav } from './components/DnorTopNav';
import { GlobalSearchPalette } from './components/GlobalSearchPalette';
import { DnorShellProvider, useDnorShell } from './context/DnorShellContext';
import { ThemeToggle } from './components/ThemeToggle';
import { ExportMenu } from './components/ExportMenu';

import {
  formatEpoch,
  formatCompactRelativeTime,
  formatRelativeTime,
  isCondensedViewport,
} from './utils/format';

// ────────────────────────────────────────────────────────────
// Helpers de tag das seções
// ────────────────────────────────────────────────────────────

function useWindowWidth() {
  const [width, setWidth] = useState(window.innerWidth);
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | null = null;
    const handler = () => {
      if (timer) clearTimeout(timer);
      timer = setTimeout(() => setWidth(window.innerWidth), 120);
    };
    window.addEventListener('resize', handler);
    return () => window.removeEventListener('resize', handler);
  }, []);
  return width;
}

// ────────────────────────────────────────────────────────────
// Root App
// ────────────────────────────────────────────────────────────

export function App() {
  return (
    <DnorShellProvider>
      <AppContent />
    </DnorShellProvider>
  );
}

function AppContent() {
  const { view } = useDnorShell();
  // Hook de resize para rerender das pills/tags responsivos
  useWindowWidth();

  // Initialize theme (dark mode support)
  useTheme();

  const { data: live, error: liveError } = useLiveOverview();
  const { summary, catalog, reports, error: snapshotError } = useSnapshot();
  const { data: corootAlerts, error: corootError, lastFetchAt: corootFetchAt } = useCorootAlerts();
  const { data: corootIncidents, error: corootIncidentsError, lastFetchAt: corootIncidentsFetchAt } = useCorootIncidents();
  const { data: longhornData, error: longhornError } = useStorageHealth();
  const { data: cronJobsData, error: cronJobsError } = useCronJobs();
  const { data: ingressesData, error: ingressesError } = useIngresses();
  const { data: certsData, error: certsError } = useCertificates();
  const { data: workloadsData, error: workloadsError } = useWorkloads();
  const { data: namespacesData, error: namespacesError } = useNamespaces();

  // Histórico acumulado de métricas de nós (para os sparklines do hover card)
  const [nodeHistory, setNodeHistory] = useState<Record<
    string,
    {
      cpu: { timestamp: number; value: number }[];
      mem: { timestamp: number; value: number }[];
      disk: { timestamp: number; value: number }[];
    }
  >>({});

  // Seed sparklines once from Prometheus historical data (last 60m at 5m steps).
  // After seeding, the accumulation effect below appends real-time points on top.
  const [nodeHistorySeeded, setNodeHistorySeeded] = useState(false);
  useEffect(() => {
    if (nodeHistorySeeded || !live?.metrics?.node_history) return;
    const seeded: Record<string, { cpu: { timestamp: number; value: number }[]; mem: { timestamp: number; value: number }[]; disk: { timestamp: number; value: number }[] }> = {};
    for (const [name, h] of Object.entries(live.metrics.node_history)) {
      seeded[name] = {
        cpu: h.cpu_percent_series.map((p) => ({ timestamp: p.timestamp, value: p.value })),
        mem: h.mem_percent_series.map((p) => ({ timestamp: p.timestamp, value: p.value })),
        disk: h.disk_percent_series.map((p) => ({ timestamp: p.timestamp, value: p.value })),
      };
    }
    setNodeHistory(seeded);
    setNodeHistorySeeded(true);
  }, [live?.metrics?.node_history, nodeHistorySeeded]);

  useEffect(() => {
    if (live?.node_metrics) {
      const ts = live.refreshed_at_epoch;
      setNodeHistory((prev) => {
        const next = { ...prev };
        let modified = false;
        for (const [nodeName, metrics] of Object.entries(live.node_metrics)) {
          if (!next[nodeName]) {
            next[nodeName] = { cpu: [], mem: [], disk: [] };
          }
          const cpuArr = [...next[nodeName].cpu];
          const memArr = [...next[nodeName].mem];
          const diskArr = [...next[nodeName].disk];
          let nodeModified = false;

          if (cpuArr.length === 0 || cpuArr[cpuArr.length - 1].timestamp !== ts) {
            cpuArr.push({ timestamp: ts, value: metrics.cpu_percent });
            memArr.push({ timestamp: ts, value: metrics.mem_percent });
            diskArr.push({ timestamp: ts, value: metrics.disk_percent });
            nodeModified = true;
          }

          if (cpuArr.length > 20) {
            cpuArr.shift();
            memArr.shift();
            diskArr.shift();
            nodeModified = true;
          }

          if (nodeModified) {
            next[nodeName] = { cpu: cpuArr, mem: memArr, disk: diskArr };
            modified = true;
          }
        }
        return modified ? next : prev;
      });
    }
  }, [live]);

  const metrics = live?.metrics ?? null;
  const condensed = isCondensedViewport();

  // Tags de seção — derivadas diretamente do estado
  const metricsSectionTag = metrics?.available
    ? `Prometheus ${metrics.window_minutes}m${metrics.stale ? ' · stale' : ''}`
    : 'Waiting for metrics';

  const opsSectionTag = live?.available
    ? `Live kube incidents${live.stale ? ' · stale' : ''}`
    : 'Waiting for live data';

  const restartSectionTag = metrics?.available
    ? `Prometheus ${metrics.window_minutes}m${metrics.stale ? ' · stale' : ''}`
    : 'Waiting for Prometheus';

  const servicesSectionTag = live?.available
    ? `Live kube ${formatEpoch(live.refreshed_at_epoch)}${live.stale ? ' · stale' : ''}`
    : 'Waiting for live data';

  const telemetrySectionTag = metrics?.available
    ? `Prometheus ${formatEpoch(metrics.refreshed_at_epoch)}${metrics.stale ? ' · stale' : ''}`
    : 'Waiting for metrics';

  const summarySectionTag = live?.available
    ? `Live kube ${formatEpoch(live.refreshed_at_epoch)}${live.stale ? ' · stale' : ''}`
    : 'Waiting for live data';

  const snapshotText = summary?.generated_at
    ? `Snapshot ${condensed ? formatCompactRelativeTime(summary.generated_at) : formatRelativeTime(summary.generated_at)}`
    : 'Waiting for snapshot';

  const errorMessage = [liveError, snapshotError].filter(Boolean).join(' | ');
  const showOverview = view === 'overview';

  return (
    <>
      <DnorTopNav liveAvailable={Boolean(live?.available)} />
      <GlobalSearchPalette live={live} />

      <main>
      <section class="shell">
        {/* ── Masthead (overview only) ── */}
        {showOverview && (
        <header class="masthead">
          <DashboardHeader snapshot={summary} live={live} metrics={metrics} corootAlerts={corootAlerts} corootIncidents={corootIncidents} />
          <SignalCard live={live} corootAlerts={corootAlerts} corootIncidents={corootIncidents} />
        </header>
        )}

        {/* ── Signal mini counters ── */}
        {showOverview && (
        <SignalGrid live={live} corootAlerts={corootAlerts} corootIncidents={corootIncidents} />
        )}

        {/* ── Node Fleet ── */}
        {(showOverview || view === 'nodes') && (
        <section class="nodes-section-band" id="dnor-nodes">
          {view === 'nodes' ? (
            <div class="dnor-page-head">
              <h1 class="dnor-page-head__title">Nodes</h1>
              <p class="dnor-page-head__subtitle">Monitor and explore your infrastructure.</p>
            </div>
          ) : (
          <div class="section-head">
            <div>
              <div class="section-kicker">Infrastructure</div>
              <div class="section-title">Node Fleet</div>
              <p>Node health, pressure conditions and capacity per node. DiskPressure causes cascading failures across services.</p>
            </div>
            <div class="section-tags">
              <span class="panel-tag">{live?.available ? `Live · ${(live.nodes ?? []).length} nós` : 'Waiting for live data'}</span>
            </div>
          </div>
          )}
          <NodesPanel live={live} history={nodeHistory} />
        </section>
        )}

        {/* ── Cluster Pressure ── */}
        {(showOverview || view === 'intel') && (
        <section class="metric-band">
          <div class="section-head">
            <div>
              <div class="section-kicker">Core load</div>
              <div class="section-title">Cluster Pressure</div>
              <p>Prometheus-backed CPU, memory and restart pressure over the current dashboard window.</p>
            </div>
            <div class="section-tags">
              <span class="panel-tag" id="metrics-section-tag">{metricsSectionTag}</span>
            </div>
          </div>
          <ClusterMetrics metrics={metrics} />
        </section>
        )}

        {showOverview && (
        <>
        <StoragePanel data={longhornData} error={longhornError} />
        <CronJobPanel data={cronJobsData} error={cronJobsError} />
        <CertExpiryPanel data={certsData} error={certsError} />
        <IngressPanel data={ingressesData} error={ingressesError} />
        <WorkloadPanel data={workloadsData} error={workloadsError} />
        <NamespacePanel data={namespacesData} error={namespacesError} />
        </>
        )}

        {(showOverview || view === 'incidents') && (
        <section class="priority-grid">
          <section class="panel priority-panel">
            <div class="section-head">
              <div>
                <div class="section-title">Immediate Action</div>
                <p>Live kube incidents first. This block should explain why an operator needs to care now.</p>
              </div>
              <div class="section-tags">
                <span class="panel-tag" id="ops-section-tag">{opsSectionTag}</span>
              </div>
            </div>
            <IncidentList live={live} />
          </section>

          <section class="panel priority-panel">
            <div class="section-head">
              <div>
                <div class="section-title">Restart Debt</div>
                <p>Prometheus-ranked restart hotspots over the last hour, rounded to discrete events.</p>
              </div>
              <div class="section-tags">
                <span class="panel-tag" id="restart-section-tag">{restartSectionTag}</span>
              </div>
            </div>
            <RestartHotspots metrics={metrics} />
          </section>
        </section>
        )}

        {showOverview && (
        <div class="content-grid">
          <section class="main-stack">
            <section class="panel">
              <div class="section-head">
                <div>
                  <div class="section-title">Critical Services</div>
                  <p>Live kube health, readiness, restart count and serving routes for the tracked surface.</p>
                </div>
                <div class="section-tags">
                  <span class="panel-tag" id="services-section-tag">{servicesSectionTag}</span>
                </div>
              </div>
              <ServiceGrid live={live} alerts={corootAlerts?.alerts ?? []} incidents={corootIncidents?.incidents ?? []} />
            </section>

            <section class="panel">
              <div class="section-head">
                <div>
                  <div class="section-title">Service Telemetry</div>
                  <p>Prometheus time-series stay close to service health so the board reads like an action surface.</p>
                </div>
                <div class="section-tags">
                  <span class="panel-tag" id="telemetry-section-tag">{telemetrySectionTag}</span>
                </div>
              </div>
              <TelemetryGrid metrics={metrics} live={live} />
            </section>
          </section>

          <aside class="rail-stack">
            <CorootIncidentsPanel
              data={corootIncidents}
              error={corootIncidentsError}
              lastFetchAt={corootIncidentsFetchAt}
            />
            <CorootAlertsPanel
              data={corootAlerts}
              error={corootError}
              lastFetchAt={corootFetchAt}
            />

            <section class="panel">
              <div class="section-head">
                <div>
                  <div class="section-title">Runtime Summary</div>
                  <p>Operational rollup only. This panel should not depend on snapshot interpretation.</p>
                </div>
                <div class="section-tags">
                  <span class="panel-tag" id="summary-section-tag">{summarySectionTag}</span>
                </div>
              </div>
              <RuntimeSummary live={live} />
            </section>

            <section class="panel">
              <div class="section-head">
                <div>
                  <div class="section-title">Catalog Snapshot</div>
                  <p>Snapshot-derived counts stay visible, but secondary to live operations.</p>
                </div>
                <div class="section-tags">
                  <span class="panel-tag" id="catalog-summary-tag">{snapshotText}</span>
                </div>
              </div>
              <CatalogSummary summary={summary} />
            </section>

            <section class="panel">
              <div class="section-head">
                <div>
                  <div class="section-title">Language Mix</div>
                  <p>Repo composition is still useful context when deciding where to intervene.</p>
                </div>
              </div>
              <LanguageBars summary={summary} />
            </section>
          </aside>
        </div>
        )}

        {view === 'intel' && (
        <div class="content-grid content-grid--intel">
          <aside class="rail-stack rail-stack--full">
            <CorootIncidentsPanel
              data={corootIncidents}
              error={corootIncidentsError}
              lastFetchAt={corootIncidentsFetchAt}
            />
            <CorootAlertsPanel
              data={corootAlerts}
              error={corootError}
              lastFetchAt={corootFetchAt}
            />
          </aside>
        </div>
        )}

        {(showOverview || view === 'reports') && (
        <section class="catalog-zone">
          <div class="catalog-shell">
            <div class="catalog-head">
              <div>
                <div class="section-kicker">{view === 'reports' ? 'Reports' : 'Secondary surface'}</div>
                <h2>{view === 'reports' ? 'Deploy reports & catalog' : 'Catalog and deploy context'}</h2>
              </div>
              <div>
                <p>
                  Deploy paths, artifact bundle and snapshot inventory remain available without stealing
                  first-fold attention from operations.
                </p>
                <div class="section-tags">
                  <span class="panel-tag" id="catalog-zone-tag">{snapshotText}</span>
                  <span class="panel-tag route-tag">Routes: /api/live/overview, /api/catalog, /api/reports</span>
                </div>
              </div>
            </div>

            <div class="catalog-layout">
              <div class="catalog-main">
                <CatalogTable catalog={catalog} summary={summary} />
              </div>
              <aside class="catalog-side">
                <section>
                  <div class="section-head">
                    <div>
                      <div class="section-title">Artifact Library</div>
                      <p>Static report bundle served from the image snapshot.</p>
                    </div>
                  </div>
                  <ArtifactList reports={reports} />
                </section>
              </aside>
            </div>
          </div>
        </section>
        )}

        {view === 'settings' && (
        <section class="panel dnor-settings">
          <div class="dnor-page-head">
            <h1 class="dnor-page-head__title">Settings</h1>
            <p class="dnor-page-head__subtitle">Appearance and export preferences.</p>
          </div>
          <div class="dnor-settings__grid">
            <div class="dnor-settings__card">
              <h3>Theme</h3>
              <p>Cycle light, dark or system auto.</p>
              <ThemeToggle />
            </div>
            <div class="dnor-settings__card">
              <h3>Export</h3>
              <p>Download live overview data.</p>
              <ExportMenu live={live} metrics={metrics} />
            </div>
            <div class="dnor-settings__card">
              <h3>Node thresholds</h3>
              <p>Configure CPU, memory and disk alert thresholds in the Nodes view.</p>
            </div>
          </div>
        </section>
        )}
      </section>

      {errorMessage && (
        <div id="error-box">
          <div class="error">{errorMessage}</div>
        </div>
      )}
    </main>
    </>
  );
}
