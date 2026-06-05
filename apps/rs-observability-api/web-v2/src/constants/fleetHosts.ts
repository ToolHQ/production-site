/** SSDNodes dedicated host — alinhado com Node Fleet (`external_nodes.json` / `hostname -f`). */
export const SSDNODES_HOSTNAME = 'ssdnodes-6a12f10c9ef11';
/** @deprecated ops-only SSH alias — não exibir na UI */
export const SSDNODES_SSH_HOST = 'ssdnodes-6a12f10c9ef11';
export const SSDNODES_IP = '104.225.218.78';

/** Hosts selecionáveis no Fleet Copilot (T-333) — ids alinhados ao manifest server-side. */
export const FLEET_CHAT_HOSTS: { id: string; label: string }[] = [
  { id: 'k8s-node-1', label: 'k8s-node-1 · OCI worker' },
  { id: 'k8s-node-2', label: 'k8s-node-2 · OCI worker' },
  { id: 'k8s-master', label: 'k8s-master · OCI control plane' },
  { id: SSDNODES_HOSTNAME, label: `${SSDNODES_HOSTNAME} · SSDNodes` },
  { id: 'hetzner-cax21-helsinki', label: 'hetzner-cax21 · builder' },
  { id: 'ip-172-31-65-56', label: 'AWS honeypot (ip-172-31-65-56)' },
];
