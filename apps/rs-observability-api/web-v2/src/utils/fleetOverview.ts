import type { HoneypotNodeStats, NodeStat, TimeSeriesPoint } from '../types/api';

export type FleetStatus = 'honeypot' | 'online' | 'degraded' | 'offline';

export interface FleetOverviewRow {
  key: string;
  status: FleetStatus;
  name: string;
  subtitle?: string;
  cluster: string;
  ip: string;
  asn: string;
  asnLabel: string;
  totalRequests: number | null;
  last24h: number | null;
  classified: boolean | null;
  requests24h: TimeSeriesPoint[];
  requests7d: TimeSeriesPoint[];
  isHoneypot: boolean;
  monitorHref?: string;
}

const CLUSTER_ASN: Record<string, { asn: string; label: string }> = {
  'OCI-K8S': { asn: '31898', label: 'Oracle' },
  'AWS-EC2': { asn: '16509', label: 'AWS' },
  HETZNER: { asn: '24940', label: 'Hetzner' },
  'SSD-NODES': { asn: '55286', label: 'B2 Net' },
};

function asnForCluster(cluster: string): { asn: string; label: string } {
  return CLUSTER_ASN[cluster] ?? { asn: '—', label: 'External' };
}

function honeypotByHost(honeypotNodes: HoneypotNodeStats[]): Map<string, HoneypotNodeStats> {
  const map = new Map<string, HoneypotNodeStats>();
  for (const stats of honeypotNodes) {
    map.set(stats.instance_host, stats);
  }
  return map;
}

function fleetStatus(node: NodeStat, honeypot?: HoneypotNodeStats): FleetStatus {
  if (honeypot?.available) return 'honeypot';
  if (node.ready) return 'online';
  if (node.disk_pressure || node.memory_pressure) return 'degraded';
  return 'offline';
}

export function buildFleetOverviewRows(
  nodes: NodeStat[],
  honeypotNodes: HoneypotNodeStats[],
): FleetOverviewRow[] {
  const honeypots = honeypotByHost(honeypotNodes);

  return nodes.map((node) => {
    const honeypot = honeypots.get(node.ip);
    const { asn, label } = asnForCluster(node.cluster);
    const isClassified = honeypot?.available ? (honeypot.classified ?? 0) > 0 : null;

    return {
      key: `${node.cluster}:${node.name}:${node.ip}`,
      status: fleetStatus(node, honeypot),
      name: node.cluster === 'AWS-EC2' && honeypot ? 'AWS-EC2' : node.name,
      subtitle: honeypot?.id ?? node.name,
      cluster: node.cluster,
      ip: node.ip,
      asn,
      asnLabel: label,
      totalRequests: honeypot?.available ? honeypot.total : null,
      last24h: honeypot?.available ? honeypot.last24h : null,
      classified: isClassified,
      requests24h: honeypot?.requests_24h ?? [],
      requests7d: honeypot?.requests_7d ?? [],
      isHoneypot: Boolean(honeypot),
      monitorHref: honeypot?.available
        ? `https://${honeypot.instance_host}:3500/monitor`
        : undefined,
    };
  });
}

export function filterFleetRows(rows: FleetOverviewRow[], query: string): FleetOverviewRow[] {
  if (!query.trim()) return rows;
  const q = query.toLowerCase();
  return rows.filter(
    (row) =>
      row.name.toLowerCase().includes(q) ||
      row.subtitle?.toLowerCase().includes(q) ||
      row.cluster.toLowerCase().includes(q) ||
      row.ip.includes(q) ||
      row.asn.includes(q) ||
      row.asnLabel.toLowerCase().includes(q) ||
      row.status.includes(q),
  );
}
