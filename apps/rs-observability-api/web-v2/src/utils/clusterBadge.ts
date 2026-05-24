export function clusterBadgeSlug(cluster: string): string {
  switch (cluster) {
    case 'OCI-K8S':
      return 'oci';
    case 'HETZNER':
      return 'hetzner';
    case 'SSD-NODES':
      return 'ssd-nodes';
    case 'AWS-EC2':
      return 'aws-ec2';
    default:
      return cluster.toLowerCase().replace(/[^a-z0-9]+/g, '-');
  }
}

export function clusterBadgeClass(cluster: string): string {
  const slug = clusterBadgeSlug(cluster);
  const known = new Set(['oci', 'hetzner', 'ssd-nodes', 'aws-ec2']);
  return known.has(slug) ? `node-cluster-badge--${slug}` : 'node-cluster-badge--external';
}
