import type { LiveOverview, SnapshotSummary } from '../types/api';
import { formatDiscreteCount } from '../utils/format';

// ────────────────────────────────────────────────────────────
// SummaryCard (átomo)
// ────────────────────────────────────────────────────────────

interface SummaryCardProps {
  label: string;
  value: string;
  detail: string;
}

function SummaryCard({ label, value, detail }: SummaryCardProps) {
  return (
    <article class="summary-card">
      <strong>{value}</strong>
      <span>{label}</span>
      <span>{detail}</span>
    </article>
  );
}

// ────────────────────────────────────────────────────────────
// RuntimeSummary (live)
// ────────────────────────────────────────────────────────────

interface RuntimeSummaryProps {
  live: LiveOverview | null;
}

export function RuntimeSummary({ live }: RuntimeSummaryProps) {
  const servicesNeedingAction = (live?.summary.down_services || 0) + (live?.summary.degraded_services || 0);

  if (!live) {
    return (
      <div class="summary-grid" id="summary-grid">
        <SummaryCard label="Waiting for summary" value="-" detail="" />
      </div>
    );
  }

  return (
    <div class="summary-grid" id="summary-grid">
      <SummaryCard
        label="Healthy coverage"
        value={`${live.summary.healthy_services ?? 0}/${live.summary.critical_services ?? 0}`}
        detail="critical services currently serving"
      />
      <SummaryCard
        label="Services needing action"
        value={formatDiscreteCount(servicesNeedingAction)}
        detail={`${live.summary.down_services ?? 0} down · ${live.summary.degraded_services ?? 0} degraded`}
      />
      <SummaryCard
        label="Runtime pods"
        value={`${live.summary.running_pods ?? 0}/${live.summary.total_pods ?? 0}`}
        detail={`${formatDiscreteCount(live.summary.restarting_pods ?? 0)} with restarts`}
      />
      <SummaryCard
        label="Watch scope"
        value={formatDiscreteCount(live.summary.affected_namespaces ?? 0)}
        detail={`${live.summary.nodes_ready ?? 0}/${live.summary.nodes_total ?? 0} ready nodes`}
      />
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// CatalogSummary (snapshot)
// ────────────────────────────────────────────────────────────

interface CatalogSummaryProps {
  summary: SnapshotSummary | null;
}

export function CatalogSummary({ summary }: CatalogSummaryProps) {
  if (!summary) {
    return (
      <div class="catalog-summary-grid" id="catalog-summary-grid">
        <SummaryCard label="Snapshot" value="-" detail="waiting for catalog summary" />
      </div>
    );
  }

  return (
    <div class="catalog-summary-grid" id="catalog-summary-grid">
      <SummaryCard
        label="Deployable apps"
        value={`${summary.deployable_app_count}/${summary.app_count}`}
        detail={`${summary.missing_deploy_script_count} missing deploy scripts`}
      />
      <SummaryCard
        label="Components tracked"
        value={formatDiscreteCount(summary.component_count)}
        detail={`${summary.cluster_workload_count} cluster workloads cataloged`}
      />
      <SummaryCard
        label="Repo-only surface"
        value={formatDiscreteCount(summary.repo_only_app_count + summary.repo_only_component_count)}
        detail={`${summary.cluster_only_count} cluster-only entries`}
      />
      <SummaryCard
        label="Catalog drift"
        value={formatDiscreteCount(summary.undocumented_count)}
        detail="undocumented entries still need classification"
      />
    </div>
  );
}
