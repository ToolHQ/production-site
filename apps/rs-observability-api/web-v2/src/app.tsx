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
import { FleetCopilotPage } from './components/FleetCopilotPage';
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
import { FleetCopilotProvider, useFleetCopilot } from './context/FleetCopilotContext';
import { useCopilotStatus } from './hooks/useCopilotStatus';
import { ThemeToggle } from './components/ThemeToggle';
import { ExportMenu } from './components/ExportMenu';
import { OverviewSectionNav } from './components/OverviewSectionNav';
import { PlatformFold } from './components/PlatformFold';

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
      <FleetCopilotProvider>
        <AppContent />
      </FleetCopilotProvider>
    </DnorShellProvider>
  );
}

function AppContent() {
  const { view } = useDnorShell();
  const { session: copilotSession } = useFleetCopilot();
  const isCopilotView = view === 'fleet-copilot';
  const copilotStatus = useCopilotStatus(isCopilotView && copilotSession.authenticated);
  // Hook de resize para rerender das pills/tags responsivos
  useWindowWidth();

  // Initialize theme (dark mode support)
  useTheme();

  useEffect(() => {
    const on = view === 'fleet-copilot';
    document.body.classList.toggle('dnor-view-fleet-copilot', on);
    document.documentElement.classList.toggle('dnor-view-fleet-copilot', on);
    return () => {
      document.body.classList.remove('dnor-view-fleet-copilot');
      document.documentElement.classList.remove('dnor-view-fleet-copilot');
    };
  }, [view]);

  const { data: live, error: liveError, lastFetchAt: liveFetchAt } = useLiveOverview();
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

          if (cpuArr.length === 0 || cpuArr[cpuArr.length - 1].timestamp !== ts) {
            cpuArr.push({ timestamp: ts, value: metrics.cpu_percent });
            memArr.push({ timestamp: ts, value: metrics.mem_percent });
            diskArr.push({ timestamp: ts, value: metrics.disk_percent });
            modified = true;
          }

          if (cpuArr.length > 20) {
            cpuArr.shift();
            memArr.shift();
            diskArr.shift();
            modified = true;
          }

          if (modified) {
            next[nodeName] = { cpu: cpuArr, mem: memArr, disk: diskArr };
          }
        }
        return next;
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
  const liveConnecting = liveFetchAt === null && !liveError;
  const showOverview = view === 'overview';
  const liveStale = Boolean(live?.available && live.stale);

  return (
    <>
      <DnorTopNav
        liveAvailable={Boolean(live?.available)}
        liveConnecting={liveConnecting}
        copilotQuota={
          copilotStatus
            ? {
                remaining: copilotStatus.rate_limit_remaining,
                max: copilotStatus.rate_limit_max,
              }
            : null
        }
      />
      {liveStale && !errorMessage && (
        <div class="dnor-stale-banner" role="status">
          <span aria-hidden="true">⏱</span>
          <p>
            Dados live em cache stale — confirme conectividade antes de triagem crítica.
            {live?.refreshed_at_epoch
              ? ` Último refresh: ${formatEpoch(live.refreshed_at_epoch)}.`
              : ''}
          </p>
        </div>
      )}
      {errorMessage && (
        <div class="dnor-alert-banner" role="alert">
          <span class="dnor-alert-banner__icon" aria-hidden="true">
            ⚠
          </span>
          <p class="dnor-alert-banner__text">{errorMessage}</p>
        </div>
      )}
      <GlobalSearchPalette live={live} />

      {isCopilotView ? (
        <main class="main--fleet-copilot">
          <section class="shell shell--fleet-copilot" id="dnor-fleet-copilot">
            <FleetCopilotPage />
          </section>
        </main>
      ) : (
      <main>
      <section class="shell">
        {/* ── Masthead (overview only) ── */}
        {showOverview && (
        <header class="masthead masthead--compact masthead--overview">
          <div class="masthead__hero">
            <DashboardHeader snapshot={summary} live={live} metrics={metrics} corootAlerts={corootAlerts} corootIncidents={corootIncidents} />
            <SignalCard live={live} corootAlerts={corootAlerts} corootIncidents={corootIncidents} />
          </div>
          <SignalGrid live={live} corootAlerts={corootAlerts} corootIncidents={corootIncidents} />
          <OverviewSectionNav />
        </header>
        )}

        {/* ── Node Fleet ── */}
        {(showOverview || view === 'nodes') && (
        <section class="nodes-section-band" id="dnor-nodes">
          {view === 'nodes' ? (
            <div class="dnor-page-head">
              <h1 class="dnor-page-head__title">Nós da fleet</h1>
              <p class="dnor-page-head__subtitle">Saúde, pressão e capacidade por host — OCI, SSDNodes, Hetzner e AWS.</p>
            </div>
          ) : (
          <div class="section-head">
            <div>
              <div class="section-kicker">Infraestrutura</div>
              <div class="section-title">Nós da fleet</div>
              <p>Saúde, pressão de disco e capacidade por nó — DiskPressure derruba serviços em cascata.</p>
            </div>
            <div class="section-tags">
              <span class="panel-tag">{live?.available ? `Live · ${(live.nodes ?? []).length} nós` : 'Aguardando dados live'}</span>
            </div>
          </div>
          )}
          <NodesPanel live={live} history={nodeHistory} />
        </section>
        )}

        {/* ── Cluster Pressure ── */}
        {(showOverview || view === 'intel') && (
        <section class="metric-band" id="dnor-metrics">
          <div class="section-head">
            <div>
              <div class="section-kicker">Carga do cluster</div>
              <div class="section-title">Pressão Prometheus</div>
              <p>CPU, memória e restarts agregados na janela do dashboard.</p>
            </div>
            <div class="section-tags">
              <span class="panel-tag" id="metrics-section-tag">{metricsSectionTag}</span>
            </div>
          </div>
          <ClusterMetrics metrics={metrics} />
        </section>
        )}

        {showOverview && (
        <PlatformFold panelCount={6}>
          <StoragePanel data={longhornData} error={longhornError} />
          <CronJobPanel data={cronJobsData} error={cronJobsError} />
          <CertExpiryPanel data={certsData} error={certsError} />
          <IngressPanel data={ingressesData} error={ingressesError} />
          <WorkloadPanel data={workloadsData} error={workloadsError} />
          <NamespacePanel data={namespacesData} error={namespacesError} />
        </PlatformFold>
        )}

        {view === 'incidents' && (
          <div class="dnor-page-head">
            <h1 class="dnor-page-head__title">Incidentes</h1>
            <p class="dnor-page-head__subtitle">
              Pods com restarts e hotspots Prometheus — priorize o que exige atenção agora.
            </p>
          </div>
        )}

        {(showOverview || view === 'incidents' || view === 'intel') && (
        <section class="priority-grid" id="dnor-incidents">
          <section class="panel priority-panel">
            <div class="section-head">
              <div>
                <div class="section-kicker">Ação imediata</div>
                <div class="section-title">Incidentes live</div>
                <p>Pods com restarts ou falhas de readiness no cluster — triagem antes de escalar.</p>
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
                <div class="section-kicker">Dívida de estabilidade</div>
                <div class="section-title">Hotspots de restart</div>
                <p>Ranking Prometheus na última hora — workloads que mais reiniciaram.</p>
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
        <div class="content-grid" id="dnor-services">
          <section class="main-stack">
            <section class="panel">
              <div class="section-head">
                <div>
                  <div class="section-kicker">Serviços críticos</div>
                  <div class="section-title">Saúde live</div>
                  <p>Readiness, restarts e rotas dos workloads monitorados.</p>
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
                  <div class="section-kicker">Telemetria</div>
                  <div class="section-title">Séries Prometheus</div>
                  <p>Métricas alinhadas à saúde dos serviços — leitura operacional.</p>
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
                  <div class="section-title">Resumo operacional</div>
                  <p>Rollup live do cluster — independente do snapshot de deploy.</p>
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
                  <div class="section-title">Snapshot do catálogo</div>
                  <p>Contagens do inventário no bundle — contexto secundário à triagem live.</p>
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
                  <div class="section-title">Mix de linguagens</div>
                  <p>Composição do repositório no snapshot — útil para priorizar intervenções.</p>
                </div>
              </div>
              <LanguageBars summary={summary} />
            </section>
          </aside>
        </div>
        )}

        {view === 'intel' && (
        <>
          <div class="dnor-page-head">
            <h1 class="dnor-page-head__title">Intel & SLO</h1>
            <p class="dnor-page-head__subtitle">Alertas e incidentes Coroot — visão focada fora do Overview.</p>
          </div>
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
        </>
        )}

        {(showOverview || view === 'reports') && (
        <section class="catalog-zone" id="dnor-catalog">
          {view === 'reports' && (
            <div class="dnor-page-head">
              <h1 class="dnor-page-head__title">Relatórios</h1>
              <p class="dnor-page-head__subtitle">Catálogo de artefatos e inventário de deploy no snapshot.</p>
            </div>
          )}
          <div class="catalog-shell">
            <div class="catalog-head">
              <div>
                <div class="section-kicker">{view === 'reports' ? 'Inventário' : 'Contexto secundário'}</div>
                <h2>{view === 'reports' ? 'Catálogo e biblioteca' : 'Catálogo e contexto de deploy'}</h2>
              </div>
              <div>
                <p>
                  Inventário de artefatos e paths de deploy — disponível sem competir com a triagem operacional.
                </p>
                <div class="section-tags">
                  <span class="panel-tag" id="catalog-zone-tag">{snapshotText}</span>
                  {showOverview && (
                    <a class="dnor-catalog-cta" href="#reports">
                      Ver catálogo completo →
                    </a>
                  )}
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
                      <div class="section-title">Biblioteca de artefatos</div>
                      <p>Relatórios estáticos servidos do bundle da imagem em execução.</p>
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
            <h1 class="dnor-page-head__title">Configurações</h1>
            <p class="dnor-page-head__subtitle">Aparência, exportação e preferências do console.</p>
          </div>
          <div class="dnor-settings__grid">
            <div class="dnor-settings__card">
              <h3>Aparência</h3>
              <p>Claro, escuro ou automático (preferência do sistema).</p>
              <ThemeToggle />
            </div>
            <div class="dnor-settings__card">
              <h3>Exportação</h3>
              <p>Baixar overview live e métricas em JSON/CSV.</p>
              <ExportMenu live={live} metrics={metrics} />
            </div>
            <div class="dnor-settings__card">
              <h3>Limites dos nós</h3>
              <p>CPU, memória e disco — ajuste na view Nós (ícone de engrenagem).</p>
            </div>
          </div>
        </section>
        )}
      </section>

    </main>
      )}
    </>
  );
}
