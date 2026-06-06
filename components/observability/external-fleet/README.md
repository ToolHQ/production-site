# External Fleet — Prometheus Endpoints

Manifests gerados automaticamente. Fonte: `config/external-fleet/registry.yaml`.

## Aplicar no cluster

```bash
kubectl apply -f components/observability/external-fleet/generated/
```

## Nós registrados

- **hetzner-cax21** — `HETZNER` @ `37.27.85.100` (`hetzner-node-exporter`)
- **ssdnodes-monstro** — `SSD-NODES` @ `104.225.218.78` (`ssdnodes-node-exporter`)
- **aws-ec2-fleet-01** — `AWS-EC2` @ `honeypot.dnor.io` (`aws-ec2-fleet-01-node-exporter`)
  - honeypot metrics: `aws-ec2-fleet-01-honeypot-metrics` → `/internal/metrics` (HTTPS :443)
