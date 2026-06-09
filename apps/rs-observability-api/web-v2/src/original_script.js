const generatedAt = document.getElementById("generated-at");
      const liveRefresh = document.getElementById("live-refresh");
      const metricsRefresh = document.getElementById("metrics-refresh");
      const liveMode = document.getElementById("live-mode");
      const autoRefresh = document.getElementById("auto-refresh");
      const healthScore = document.getElementById("health-score");
      const healthCopy = document.getElementById("health-copy");
      const nextAction = document.getElementById("next-action");
      const signalCard = document.getElementById("signal-card");
      const signalGrid = document.getElementById("signal-grid");
      const clusterMetrics = document.getElementById("cluster-metrics");
      const incidentList = document.getElementById("incident-list");
      const restartList = document.getElementById("restart-list");
      const serviceGrid = document.getElementById("service-grid");
      const telemetryGrid = document.getElementById("telemetry-grid");
      const summaryGrid = document.getElementById("summary-grid");
      const catalogSummaryGrid = document.getElementById("catalog-summary-grid");
      const languageBars = document.getElementById("language-bars");
      const appsBody = document.getElementById("apps-body");
      const artifactList = document.getElementById("artifact-list");
      const deployableMeta = document.getElementById("deployable-meta");
      const metricsSectionTag = document.getElementById("metrics-section-tag");
      const opsSectionTag = document.getElementById("ops-section-tag");
      const restartSectionTag = document.getElementById("restart-section-tag");
      const servicesSectionTag = document.getElementById("services-section-tag");
      const telemetrySectionTag = document.getElementById("telemetry-section-tag");
      const summarySectionTag = document.getElementById("summary-section-tag");
      const catalogSummaryTag = document.getElementById("catalog-summary-tag");
      const catalogZoneTag = document.getElementById("catalog-zone-tag");
      const errorBox = document.getElementById("error-box");

      let snapshotSummary = null;
      let latestLiveOverview = null;
      let latestMetrics = null;

      function escapeHtml(value) {
        return String(value ?? "")
          .replaceAll("&", "&amp;")
          .replaceAll("<", "&lt;")
          .replaceAll(">", "&gt;")
          .replaceAll('"', "&quot;")
          .replaceAll("'", "&#39;");
      }

      function renderError(message) {
        errorBox.innerHTML = message ? `<div class="error">${escapeHtml(message)}</div>` : "";
      }

      function formatEpoch(epochSeconds) {
        if (!epochSeconds) {
          return "Waiting for refresh...";
        }
        return new Date(epochSeconds * 1000).toLocaleTimeString();
      }

      function formatRelativeTime(raw) {
        if (!raw) {
          return "timestamp unavailable";
        }
        const date = new Date(raw);
        if (Number.isNaN(date.getTime())) {
          return raw;
        }
        const diffMs = Date.now() - date.getTime();
        const minutes = Math.round(diffMs / 60000);
        const hours = Math.round(diffMs / 3600000);
        const days = Math.round(diffMs / 86400000);
        if (minutes < 1) {
          return "generated just now";
        }
        if (minutes < 60) {
          return `generated ${minutes} minute${minutes === 1 ? "" : "s"} ago`;
        }
        if (hours < 48) {
          return `generated ${hours} hour${hours === 1 ? "" : "s"} ago`;
        }
        return `generated ${days} day${days === 1 ? "" : "s"} ago`;
      }

      function isCompactViewport() {
        return window.matchMedia("(max-width: 560px)").matches;
      }

      function isCondensedViewport() {
        return window.matchMedia("(max-width: 980px)").matches;
      }

      function formatCompactRelativeTime(raw) {
        if (!raw) {
          return "time unknown";
        }
        const date = new Date(raw);
        if (Number.isNaN(date.getTime())) {
          return raw;
        }
        const diffMs = Math.max(0, Date.now() - date.getTime());
        const minutes = Math.round(diffMs / 60000);
        const hours = Math.round(diffMs / 3600000);
        const days = Math.round(diffMs / 86400000);
        if (minutes < 1) {
          return "now";
        }
        if (minutes < 60) {
          return `${minutes}m ago`;
        }
        if (hours < 48) {
          return `${hours}h ago`;
        }
        return `${days}d ago`;
      }

      function formatMetaDate(raw) {
        if (!raw) {
          return "date unavailable";
        }
        const date = new Date(raw);
        return Number.isNaN(date.getTime())
          ? raw
          : date.toLocaleString([], { month: "numeric", day: "numeric", hour: "numeric", minute: "2-digit" });
      }

      function formatShortClock(epochSeconds) {
        if (!epochSeconds) {
          return "Waiting";
        }
        return new Date(epochSeconds * 1000).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
      }

      function refreshTopMetaPills() {
        const compact = isCompactViewport();
        const condensed = isCondensedViewport();

        if (snapshotSummary) {
          generatedAt.textContent = snapshotSummary.generated_at
            ? compact
              ? `Snapshot · ${formatCompactRelativeTime(snapshotSummary.generated_at)}`
              : condensed
                ? `Snapshot · ${formatRelativeTime(snapshotSummary.generated_at).replace(/^generated\s/, "")}`
                : `Snapshot · ${formatRelativeTime(snapshotSummary.generated_at).replace(/^generated\s/, "")} · ${formatMetaDate(snapshotSummary.generated_at)}`
            : "Snapshot unavailable";
        }

        if (latestLiveOverview) {
          liveRefresh.textContent = latestLiveOverview.available
            ? `${condensed ? "Live" : "Live kube"} ${formatShortClock(latestLiveOverview.refreshed_at_epoch)}${latestLiveOverview.stale ? " · stale" : ""}`
            : "Live unavailable";
        }

        if (latestMetrics) {
          metricsRefresh.textContent = latestMetrics.available
            ? `${condensed ? "Prom" : "Prometheus"} ${formatShortClock(latestMetrics.refreshed_at_epoch)}${latestMetrics.stale ? " · stale" : ""}`
            : "Prometheus unavailable";
        }
      }

      function formatBytes(bytes) {
        if (!Number.isFinite(bytes) || bytes <= 0) {
          return "0 B";
        }
        const units = ["B", "KB", "MB", "GB", "TB"];
        let value = bytes;
        let unit = 0;
        while (value >= 1024 && unit < units.length - 1) {
          value /= 1024;
          unit += 1;
        }
        return `${value.toFixed(value >= 10 || unit === 0 ? 0 : 1)} ${units[unit]}`;
      }

      function formatPercent(value) {
        return `${Number(value || 0).toFixed(1)}%`;
      }

      function formatCores(value) {
        return `${Number(value || 0).toFixed(2)} cores`;
      }

      function formatDiscreteCount(value) {
        return Math.round(Number(value || 0)).toLocaleString();
      }

      function statusClass(status) {
        if (status === "down") {
          return "down";
        }
        if (status === "degraded") {
          return "degraded";
        }
        if (status === "healthy") {
          return "healthy";
        }
        return "telemetry";
      }

      function tableStatusClass(readiness) {
        if (readiness === "deployable") {
          return "deployable";
        }
        if (readiness === "partial") {
          return "partial";
        }
        return "wip";
      }

      function sparkline(points, color) {
        const values = Array.isArray(points) ? points.filter((point) => Number.isFinite(point.value)) : [];
        if (!values.length) {
          return `<svg class="sparkline" viewBox="0 0 220 72" preserveAspectRatio="none"><path d="M0 46 L220 46" stroke="rgba(22,32,43,0.12)" stroke-width="2" stroke-dasharray="4 6" fill="none"></path></svg>`;
        }

        const width = 220;
        const height = 72;
        const min = Math.min(...values.map((point) => point.value));
        const max = Math.max(...values.map((point) => point.value));
        const span = max - min || 1;

        const coords = values.map((point, index) => {
          const x = values.length === 1 ? 0 : (index / (values.length - 1)) * width;
          const y = height - (((point.value - min) / span) * (height - 10) + 5);
          return [x, y];
        });

        const line = coords.map(([x, y]) => `${x.toFixed(2)},${y.toFixed(2)}`).join(" ");
        const area = `0,${height} ${line} ${width},${height}`;

        return `
          <svg class="sparkline" viewBox="0 0 ${width} ${height}" preserveAspectRatio="none">
            <polyline points="${area}" fill="${color}18" stroke="none"></polyline>
            <polyline points="${line}" fill="none" stroke="${color}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"></polyline>
          </svg>
        `;
      }

      function summaryCard(label, value, detail) {
        return `
          <article class="summary-card">
            <strong>${escapeHtml(value)}</strong>
            <span>${escapeHtml(label)}</span>
            <span>${escapeHtml(detail)}</span>
          </article>
        `;
      }

      function incidentsBySeverity(live, severity) {
        const incidents = Array.isArray(live?.incidents) ? live.incidents : [];
        return incidents.filter((incident) => incident.severity === severity).length;
      }

      function restartHotspots(metrics) {
        const hotspots = Array.isArray(metrics?.top_restarts) ? metrics.top_restarts : [];
        return hotspots.filter((item) => Math.round(Number(item.restarts_last_hour || 0)) > 0);
      }

      function deltaFromSeries(points) {
        const values = Array.isArray(points) ? points.filter((point) => Number.isFinite(point.value)) : [];
        if (values.length < 2) {
          return null;
        }
        return values[values.length - 1].value - values[0].value;
      }

      function describeDelta(kind, delta) {
        if (!Number.isFinite(delta)) {
          return "trend unavailable";
        }

        if (kind === "restart") {
          const rounded = Math.round(Math.abs(delta));
          if (rounded < 1) {
            return "stable vs window start";
          }
          return delta > 0
            ? `+${rounded} events vs window start`
            : `${rounded} fewer events vs window start`;
        }

        const absDelta = Math.abs(delta);
        if (absDelta < 1.5) {
          return "steady vs window start";
        }
        return delta > 0
          ? `rising ${absDelta.toFixed(1)} pts vs window start`
          : `down ${absDelta.toFixed(1)} pts vs window start`;
      }

      function metricState(kind, value) {
        if (kind === "restart") {
          if (value >= 10) {
            return { tone: "critical", badge: "Restart spike" };
          }
          if (value > 0) {
            return { tone: "warning", badge: "Restarts active" };
          }
          return { tone: "healthy", badge: "Quiet hour" };
        }

        if (kind === "cpu") {
          if (value >= 85) {
            return { tone: "critical", badge: "High load" };
          }
          if (value >= 65) {
            return { tone: "warning", badge: "Elevated" };
          }
          return { tone: "healthy", badge: "Within headroom" };
        }

        if (value >= 85) {
          return { tone: "critical", badge: "Memory pressure" };
        }
        if (value >= 70) {
          return { tone: "warning", badge: "Warm memory" };
        }
        return { tone: "healthy", badge: "Within headroom" };
      }

      function boardLabel(live, metrics) {
        if (!live?.available) {
          return {
            tone: "critical",
            mode: "Snapshot fallback",
            score: "Live unavailable",
            copy: live?.error || "The in-cluster Kubernetes API is not reachable from this runtime."
          };
        }

        const criticalIncidents = incidentsBySeverity(live, "critical");
        const warningIncidents = incidentsBySeverity(live, "warning");
        const downServices = live.summary.down_services || 0;
        const degradedServices = live.summary.degraded_services || 0;
        const restartingPods = live.summary.restarting_pods || 0;
        const hotspots = restartHotspots(metrics);
        const criticalWatch = criticalIncidents + downServices;
        const warningWatch = warningIncidents + degradedServices + (restartingPods > 0 ? 1 : 0) + hotspots.length;

        if (criticalWatch > 0) {
          return {
            tone: "critical",
            mode: live.stale || metrics?.stale ? "Immediate attention · stale signal" : "Immediate attention",
            score: `${criticalWatch} blocker${criticalWatch === 1 ? "" : "s"}`,
            copy: `${criticalIncidents} critical incident${criticalIncidents === 1 ? "" : "s"} and ${downServices} service${downServices === 1 ? "" : "s"} down are active on the board.`
          };
        }

        if (warningWatch > 0 || live.stale || metrics?.stale) {
          return {
            tone: "warning",
            mode: live.stale || metrics?.stale ? "Guarded operation · stale cache" : "Guarded operation",
            score: `${warningWatch || 1} watchpoint${warningWatch === 1 ? "" : "s"}`,
            copy: "No hard outage, but degraded services, warning incidents or restart debt still require follow-up."
          };
        }

        return {
          tone: "healthy",
          mode: "Live watch green",
          score: "0 blockers",
          copy: "No critical incident, no down service and no restart hotspot are dominating the board right now."
        };
      }

      function nextActionText(live, metrics) {
        if (!live?.available) {
          return "Restore in-cluster Kubernetes API reachability before trusting the board.";
        }

        const incidents = Array.isArray(live.incidents) ? live.incidents : [];
        const criticalIncident = incidents.find((incident) => incident.severity === "critical");
        const warningIncident = incidents.find((incident) => incident.severity === "warning");
        const hotspots = restartHotspots(metrics);

        if (criticalIncident) {
          return `Inspect ${criticalIncident.resource} in ${criticalIncident.namespace}; ${criticalIncident.message}`;
        }

        if ((live.summary.down_services || 0) > 0) {
          return "Open the critical service board and recover the first service marked down.";
        }

        if (hotspots.length) {
          return `Inspect ${hotspots[0].pod} in ${hotspots[0].namespace}; it carries the highest restart debt in the current window.`;
        }

        if ((live.summary.degraded_services || 0) > 0) {
          return "Review degraded services before the board turns red.";
        }

        if (warningIncident) {
          return `Review ${warningIncident.resource} in ${warningIncident.namespace} before it escalates.`;
        }

        if (live.stale || metrics?.stale) {
          return "Fresh data is degraded; confirm the live data path before treating this as steady state.";
        }

        return "No immediate blocker. Stay on telemetry and watch for new restart hotspots.";
      }

      function renderSignal(live) {
        const metrics = live?.metrics || {};
        const board = boardLabel(live, metrics);
        const totalIncidents = incidentsBySeverity(live, "critical") + incidentsBySeverity(live, "warning");
        const servicesNeedingAction = (live?.summary.down_services || 0) + (live?.summary.degraded_services || 0);

        signalCard.dataset.tone = board.tone;
        liveMode.textContent = board.mode;
        healthScore.textContent = board.score;
        healthCopy.textContent = board.copy;
        nextAction.textContent = nextActionText(live, metrics);

        const metricsInterval = live?.metrics?.refresh_interval_seconds || "--";
        autoRefresh.textContent = `Kube ${live?.refresh_interval_seconds || "--"}s · Metrics ${metricsInterval}s`;

        signalGrid.innerHTML = [
          { value: totalIncidents, label: "Active incidents" },
          { value: servicesNeedingAction, label: "Services needing action" },
          { value: `${live?.summary.nodes_ready ?? "--"}/${live?.summary.nodes_total ?? "--"}`, label: "Ready nodes" },
          { value: formatDiscreteCount(live?.summary.restarting_pods ?? 0), label: "Restarting pods" }
        ].map((item) => `
          <div class="signal-mini">
            <strong>${escapeHtml(item.value)}</strong>
            <span>${escapeHtml(item.label)}</span>
          </div>
        `).join("");
      }

      function renderClusterMetrics(metrics) {
        if (!metrics?.available) {
          clusterMetrics.innerHTML = `<article class="metric-card"><div class="metric-label">Prometheus unavailable</div><div class="metric-meta">${escapeHtml(metrics?.error || "The console could not fetch time-series yet.")}</div></article>`;
          return;
        }

        const cluster = metrics.cluster || {};
        const cpuState = metricState("cpu", Number(cluster.cpu_percent_latest || 0));
        const memoryState = metricState("memory", Number(cluster.memory_percent_latest || 0));
        const restartState = metricState("restart", Number(cluster.restart_events_last_hour || 0));

        const items = [
          {
            label: "Cluster CPU",
            value: formatPercent(cluster.cpu_percent_latest),
            meta: `${formatCores(cluster.cpu_cores_used_latest)} in use · ${metrics.window_minutes}m window`,
            note: describeDelta("cpu", deltaFromSeries(cluster.cpu_percent_series || [])),
            color: "#0d7c72",
            series: cluster.cpu_percent_series || [],
            state: cpuState
          },
          {
            label: "Cluster Memory",
            value: formatPercent(cluster.memory_percent_latest),
            meta: `${formatBytes(cluster.memory_bytes_used_latest)} working set · ${metrics.window_minutes}m window`,
            note: describeDelta("memory", deltaFromSeries(cluster.memory_percent_series || [])),
            color: "#c96633",
            series: cluster.memory_percent_series || [],
            state: memoryState
          },
          {
            label: "Restart Pressure",
            value: formatDiscreteCount(cluster.restart_events_last_hour),
            meta: "restart events recorded over the last hour",
            note: describeDelta("restart", deltaFromSeries(cluster.restart_pressure_series || [])),
            color: "#c03b2b",
            series: cluster.restart_pressure_series || [],
            state: restartState
          }
        ];

        clusterMetrics.innerHTML = items.map((metric) => `
          <article class="metric-card" data-tone="${metric.state.tone}">
            <div class="metric-top">
              <div>
                <div class="metric-label">${escapeHtml(metric.label)}</div>
                <strong class="metric-value">${escapeHtml(metric.value)}</strong>
                <div class="metric-meta">${escapeHtml(metric.meta)}</div>
              </div>
              <span class="trend-chip ${metric.state.tone}">${escapeHtml(metric.state.badge)}</span>
            </div>
            <div class="metric-note">${escapeHtml(metric.note)}</div>
            ${sparkline(metric.series, metric.color)}
          </article>
        `).join("");
      }

      function renderLiveSummary(live) {
        const servicesNeedingAction = (live?.summary.down_services || 0) + (live?.summary.degraded_services || 0);

        summaryGrid.innerHTML = [
          summaryCard("Healthy coverage", `${live?.summary.healthy_services ?? 0}/${live?.summary.critical_services ?? 0}`, "critical services currently serving"),
          summaryCard("Services needing action", formatDiscreteCount(servicesNeedingAction), `${live?.summary.down_services ?? 0} down · ${live?.summary.degraded_services ?? 0} degraded`),
          summaryCard("Runtime pods", `${live?.summary.running_pods ?? 0}/${live?.summary.total_pods ?? 0}`, `${formatDiscreteCount(live?.summary.restarting_pods ?? 0)} with restarts`),
          summaryCard("Watch scope", formatDiscreteCount(live?.summary.affected_namespaces ?? 0), `${live?.summary.nodes_ready ?? 0}/${live?.summary.nodes_total ?? 0} ready nodes`)
        ].join("");
      }

      function renderCatalogSummary(summary) {
        if (!summary) {
          catalogSummaryGrid.innerHTML = summaryCard("Snapshot", "-", "waiting for catalog summary");
          return;
        }

        catalogSummaryGrid.innerHTML = [
          summaryCard("Deployable apps", `${summary.deployable_app_count}/${summary.app_count}`, `${summary.missing_deploy_script_count} missing deploy scripts`),
          summaryCard("Components tracked", formatDiscreteCount(summary.component_count), `${summary.cluster_workload_count} cluster workloads cataloged`),
          summaryCard("Repo-only surface", formatDiscreteCount(summary.repo_only_app_count + summary.repo_only_component_count), `${summary.cluster_only_count} cluster-only entries`),
          summaryCard("Catalog drift", formatDiscreteCount(summary.undocumented_count), "undocumented entries still need classification")
        ].join("");
      }

      function renderServices(live) {
        const services = Array.isArray(live?.services) ? live.services : [];
        serviceGrid.innerHTML = services.length
          ? services.map((service) => `
            <article class="service-card" data-status="${escapeHtml(service.status)}">
              <div class="service-head">
                <div>
                  <div class="service-name">${escapeHtml(service.label)}</div>
                  <div class="service-subtitle">${escapeHtml(`${service.namespace} · ${service.workload_kind} · ${service.workload_name}`)}</div>
                </div>
                <span class="status-pill ${statusClass(service.status)}">${escapeHtml(service.status)}</span>
              </div>
              <p class="service-message">${escapeHtml(service.message)}</p>
              <div class="stat-row">
                <div class="stat-stack">
                  <strong>${escapeHtml(`${service.ready}/${service.desired}`)}</strong>
                  <span>ready vs desired</span>
                </div>
                <div class="stat-stack">
                  <strong>${escapeHtml(`${service.running_pods}/${service.pods_total}`)}</strong>
                  <span>running pods</span>
                </div>
                <div class="stat-stack">
                  <strong>${escapeHtml(formatDiscreteCount(service.restart_count))}</strong>
                  <span>restart count</span>
                </div>
                <div class="stat-stack route-stack">
                  <strong>${escapeHtml(service.route || "internal")}</strong>
                  <span>primary route</span>
                </div>
              </div>
            </article>
          `).join("")
          : `<article class="service-card"><p class="empty">Live service board unavailable.</p></article>`;
      }

      function renderTelemetry(metrics) {
        const services = Array.isArray(metrics?.services) ? metrics.services : [];
        const liveServices = new Map((latestLiveOverview?.services || []).map((service) => [service.id, service]));

        telemetryGrid.innerHTML = services.length
          ? services.map((service) => {
            const liveService = liveServices.get(service.id);
            const liveStatus = liveService?.status || "telemetry";
            const route = liveService?.route || "internal route";
            const restartCount = liveService ? formatDiscreteCount(liveService.restart_count) : "--";

            return `
              <article class="telemetry-card" data-tone="${escapeHtml(liveStatus)}">
                <div class="telemetry-header">
                  <div>
                    <div class="telemetry-name">${escapeHtml(service.label)}</div>
                    <div class="telemetry-support">Prometheus ${metrics.window_minutes}m window · ${escapeHtml(route)} · ${escapeHtml(restartCount)} live restarts</div>
                  </div>
                  <span class="status-pill ${statusClass(liveStatus)}">${escapeHtml(liveStatus)}</span>
                </div>
                <div class="telemetry-grid-mini">
                  <div class="telemetry-mini">
                    <strong class="telemetry-value">${escapeHtml(formatCores(service.cpu_cores_latest))}</strong>
                    <span class="telemetry-meta">CPU in use</span>
                    ${sparkline(service.cpu_series || [], "#0d7c72")}
                  </div>
                  <div class="telemetry-mini">
                    <strong class="telemetry-value">${escapeHtml(formatBytes(service.memory_bytes_latest))}</strong>
                    <span class="telemetry-meta">Memory RSS</span>
                    ${sparkline(service.memory_series || [], "#c96633")}
                  </div>
                </div>
              </article>
            `;
          }).join("")
          : `<article class="telemetry-card"><p class="empty">No Prometheus time-series available for tracked services.</p></article>`;
      }

      function renderIncidents(live) {
        const incidents = Array.isArray(live?.incidents) ? live.incidents.slice(0, 6) : [];
        incidentList.innerHTML = incidents.length
          ? incidents.map((incident) => `
            <article class="incident-item">
              <div class="incident-body">
                <strong>${escapeHtml(incident.resource)}</strong>
                <span>${escapeHtml(`${incident.namespace} · ${incident.message}`)}</span>
              </div>
              <span class="severity ${escapeHtml(incident.severity)}">${escapeHtml(incident.severity)}</span>
            </article>
          `).join("")
          : `<article class="incident-item"><div class="incident-body"><strong>No active incident</strong><span>The live kube board is quiet right now.</span></div><span class="severity clear">clear</span></article>`;
      }

      function renderRestartHotspots(metrics) {
        const hotspots = restartHotspots(metrics).slice(0, 6);
        restartList.innerHTML = hotspots.length
          ? hotspots.map((item) => `
            <article class="hotspot-item">
              <div class="hotspot-body">
                <strong>${escapeHtml(item.pod)}</strong>
                <span>${escapeHtml(item.namespace)}</span>
              </div>
              <strong class="hotspot-value">${escapeHtml(formatDiscreteCount(item.restarts_last_hour))}</strong>
            </article>
          `).join("")
          : `<article class="hotspot-item"><div class="hotspot-body"><strong>No restart hotspot</strong><span>The last hour is quiet for the tracked namespaces.</span></div></article>`;
      }

      function renderLanguages(summary) {
        const languages = Array.isArray(summary?.app_languages) ? summary.app_languages : [];
        const max = Math.max(...languages.map((item) => item.count), 1);
        languageBars.innerHTML = languages.length
          ? languages.map((item) => `
            <div class="language-row">
              <div class="language-head">
                <span>${escapeHtml(item.language)}</span>
                <strong>${escapeHtml(item.count)}</strong>
              </div>
              <div class="language-track"><div class="language-fill" style="width: ${(item.count / max) * 100}%"></div></div>
            </div>
          `).join("")
          : `<div class="language-row"><div class="language-head"><span>No language data</span><strong>0</strong></div><div class="language-track"><div class="language-fill" style="width: 0%"></div></div></div>`;
      }

      function renderApps(catalog) {
        const apps = Array.isArray(catalog?.apps) ? catalog.apps : [];
        const prioritizedApps = apps
          .slice()
          .sort((left, right) => {
            const score = { deployable: 0, partial: 1, wip: 2 };
            return (score[left.deploy_readiness] ?? 3) - (score[right.deploy_readiness] ?? 3)
              || left.name.localeCompare(right.name);
          })
          .slice(0, 8);

        deployableMeta.textContent = `${snapshotSummary?.deployable_app_count ?? 0} deployable · ${snapshotSummary?.missing_deploy_script_count ?? 0} without deploy path · ${snapshotSummary?.undocumented_count ?? 0} undocumented`;

        appsBody.innerHTML = prioritizedApps.length
          ? prioritizedApps.map((app) => `
            <tr>
              <td data-label="App">
                <strong>${escapeHtml(app.name)}</strong>
                <small>${escapeHtml(app.description || app.framework || "No description")}</small>
              </td>
              <td data-label="Stack">${escapeHtml([app.language || "unknown", app.framework || ""].filter(Boolean).join(" · "))}</td>
              <td data-label="Deploy Path">
                <strong>${escapeHtml(app.deploy_script || "manual / missing")}</strong>
                <small>${escapeHtml(app.exposed_port ? `port ${app.exposed_port}` : app.readiness_missing || "path available")}</small>
              </td>
              <td data-label="Readiness"><span class="table-status ${tableStatusClass(app.deploy_readiness)}">${escapeHtml(app.deploy_readiness || "unknown")}</span></td>
            </tr>
          `).join("")
          : '<tr><td colspan="4">No cataloged apps found.</td></tr>';
      }

      function renderArtifacts(reports) {
        const artifacts = Array.isArray(reports?.artifacts) ? reports.artifacts.slice(0, 8) : [];
        artifactList.innerHTML = artifacts.length
          ? artifacts.map((artifact) => `
            <article class="artifact">
              <div class="artifact-meta">
                <div>
                  <div class="artifact-kind">${escapeHtml(artifact.kind)}</div>
                  <strong><a href="${escapeHtml(artifact.href)}" target="_blank" rel="noreferrer">${escapeHtml(artifact.label)}</a></strong></div>
                <small>${escapeHtml(formatBytes(artifact.size_bytes))}</small>
              </div>
              <p>${escapeHtml(`Artifact id: ${artifact.id}`)}</p>
            </article>
          `).join("")
          : '<div class="artifact"><p>No report artifacts were bundled into this image.</p></div>';
      }

      function updateSnapshotTags(summary) {
        const condensed = isCondensedViewport();
        const snapshotText = summary?.generated_at
          ? `Snapshot ${condensed ? formatCompactRelativeTime(summary.generated_at) : formatRelativeTime(summary.generated_at)}`
          : "Snapshot unavailable";
        catalogSummaryTag.textContent = snapshotText;
        catalogZoneTag.textContent = snapshotText;
      }

      function updateLiveTags(live, metrics) {
        summarySectionTag.textContent = live.available
          ? `Live kube ${formatEpoch(live.refreshed_at_epoch)}${live.stale ? " · stale" : ""}`
          : "Live unavailable";
        opsSectionTag.textContent = live.available
          ? `Live kube incidents${live.stale ? " · stale" : ""}`
          : "Live unavailable";
        servicesSectionTag.textContent = live.available
          ? `Live kube ${formatEpoch(live.refreshed_at_epoch)}${live.stale ? " · stale" : ""}`
          : "Live unavailable";
        metricsSectionTag.textContent = metrics.available
          ? `Prometheus ${metrics.window_minutes}m${metrics.stale ? " · stale" : ""}`
          : "Prometheus unavailable";
        restartSectionTag.textContent = metrics.available
          ? `Prometheus ${metrics.window_minutes}m${metrics.stale ? " · stale" : ""}`
          : "Prometheus unavailable";
        telemetrySectionTag.textContent = metrics.available
          ? `Prometheus ${formatEpoch(metrics.refreshed_at_epoch)}${metrics.stale ? " · stale" : ""}`
          : "Prometheus unavailable";
      }

      async function loadSnapshot() {
        const [summaryResponse, catalogResponse, reportResponse] = await Promise.all([
          fetch("/api/catalog/summary", { cache: "no-store" }),
          fetch("/api/catalog", { cache: "no-store" }),
          fetch("/api/reports", { cache: "no-store" })
        ]);

        if (!summaryResponse.ok || !catalogResponse.ok || !reportResponse.ok) {
          throw new Error("Snapshot API returned an unexpected status.");
        }

        const [summary, catalog, reports] = await Promise.all([
          summaryResponse.json(),
          catalogResponse.json(),
          reportResponse.json()
        ]);

        snapshotSummary = summary;
        refreshTopMetaPills();
        updateSnapshotTags(summary);
        renderCatalogSummary(summary);
        renderLanguages(summary);
        renderApps(catalog);
        renderArtifacts(reports);
      }

      async function loadLive() {
        const response = await fetch("/api/live/overview", { cache: "no-store" });
        if (!response.ok) {
          throw new Error("Live API returned an unexpected status.");
        }

        const live = await response.json();
        latestLiveOverview = live;
        const metrics = live.metrics || {};
        latestMetrics = metrics;
        refreshTopMetaPills();
        updateLiveTags(live, metrics);
        renderSignal(live);
        renderClusterMetrics(metrics);
        renderLiveSummary(live);
        renderServices(live);
        renderTelemetry(metrics);
        renderIncidents(live);
        renderRestartHotspots(metrics);

        const errors = [];
        if (live.error) {
          errors.push(live.stale ? `Serving cached live data: ${live.error}` : live.error);
        }
        if (metrics.error) {
          errors.push(metrics.stale ? `Serving cached metrics: ${metrics.error}` : metrics.error);
        }
        renderError(errors.join(" | "));
      }

      async function bootstrap() {
        try {
          await Promise.all([loadSnapshot(), loadLive()]);
        } catch (error) {
          renderError(error.message || "Failed to load observability data.");
        }
      }

      bootstrap();
      let resizeTimer = null;
      window.addEventListener("resize", () => {
        clearTimeout(resizeTimer);
        resizeTimer = setTimeout(() => {
          refreshTopMetaPills();
          if (snapshotSummary) {
            updateSnapshotTags(snapshotSummary);
          }
        }, 120);
      });
      setInterval(() => {
        loadLive().catch((error) => renderError(error.message || "Failed to refresh live data."));
      }, 15000);
      setInterval(() => {
        loadSnapshot().catch((error) => renderError(error.message || "Failed to refresh snapshot data."));
      }, 300000);