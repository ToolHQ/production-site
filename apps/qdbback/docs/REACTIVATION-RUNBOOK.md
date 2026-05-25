# qdbback — Runbook de reativação

Ordem obrigatória das fases (2026-05-24).

## Fase 0 — Repo

- [x] `routers/` + `services/` sincronizados em `apps/qdbback/`
- [x] `apps/version.json` + docs AS-IS
- [x] PR mergeado

## Fase 1 — EC2 (as-is)

```bash
./scripts/aws-fleet/deploy-qdbback-ec2.sh --phase start
```

Validação interna na EC2:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/              # 301
curl -sk -o /dev/null -w '%{http_code}\n' https://127.0.0.1/           # 200
curl -sk -H 'Cookie: monitor-key=215eaf6a-74c4-42cf-8417-b8f395bfeea6' \
  https://127.0.0.1:3500/api/monitor/status                               # 200
```

## Fase 2 — SG + TLS + teste externo

```bash
./scripts/aws-fleet/configure-qdbback-sg.sh --apply
./scripts/aws-fleet/deploy-qdbback-ec2.sh --phase tls
```

Teste de fora:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://3.236.249.77/
curl -sk -o /dev/null -w '%{http_code}\n' https://3.236.249.77/
```

## Fase 3 — Logging end-to-end

```bash
./scripts/aws-fleet/validate-qdbback-logging.sh
```

Confirma incremento de `httpRequests` após probe externo.

## Fase 4 — Operacional

```bash
./scripts/aws-fleet/deploy-qdbback-ec2.sh --phase systemd
```

- systemd `qdbback.service`
- skip webpack em prod se `dist/monitor/` existir
- logs em `/var/log/qdbback.log`

## Fase 5 — Modernização

### 5a — Classificação heurística ✅ (este PR)

- Tags automáticas em `classification` no INSERT (`services/classifyRequest.js`)
- API `GET /api/monitor/threats` — resumo por tag
- Coluna `classification` no grid de requests

### 5b — Node Fleet honeypot ✅

- `GET /internal/threats-summary` + card no Node Fleet (`reports.dnor.io`)

### 5c — Modernização operacional (este PR)

- **Node 16.20 LTS** na EC2 (AL2 — Node 22+ exige Amazon Linux 2023)
- **Auth admin** via `/etc/qdbback/monitor.env` (`QDBBACK_MONITOR_SECRET`, `QDBBACK_MONITOR_LOGIN_KEY`)
- **GeoIP** — preenche `country` no INSERT (`geoip-lite`)
- **SQL guard** — `/api/monitor/sql` só aceita `SELECT` read-only em produção
- **Purge** — `scripts/purge-old-data.js` + timer `qdbback-purge` (applicationLogs > 30d)
- **Logrotate** — `/var/log/qdbback.log` (14 dias)

```bash
# Deploy completo 5c
./scripts/aws-fleet/deploy-qdbback-ec2.sh --phase all

# Login admin (use key do monitor.env na EC2)
ssh aws-ec2-fleet-01 'sudo grep LOGIN /etc/qdbback/monitor.env'
```

### Pendente (futuro)

- TLS Let's Encrypt — `./scripts/aws-fleet/deploy-qdbback-ec2.sh --phase letsencrypt --tls-domain honeypot.dnor.io` (DNS A → IP EC2)
- Migração AL2023 — `./scripts/aws-fleet/deploy-qdbback-ec2.sh --phase al2023` (checklist)

## Fase 5d — Prometheus (T-302) ✅

- `GET /internal/metrics` — exposition format 0.0.4 (allowlist OCI)
- Métricas: `qdbback_http_requests_total`, `_last24h`, `_classified_total`, `_unclassified_total`, `qdbback_process_uptime_seconds`, `qdbback_build_info`

```bash
# Off-cluster → 403
curl -sk https://3.236.249.77/internal/metrics

# From OCI node (allowlisted)
ssh oci-k8s-node-1 'curl -sk https://3.236.249.77/internal/metrics | head'
```

Deploy:

```bash
./scripts/aws-fleet/deploy-qdbback-ec2.sh --phase sync
./scripts/aws-fleet/deploy-qdbback-ec2.sh --phase start
```

## Fase 5e — Let's Encrypt

Pré-requisito: registro DNS **`honeypot.dnor.io`** A → `3.236.249.77`.

```bash
./scripts/aws-fleet/deploy-qdbback-ec2.sh --phase letsencrypt --tls-domain honeypot.dnor.io
```

Após sucesso, atualizar `config/external-fleet/registry.yaml` / scrape rs-observability se migrar hostname.

## Fase 6 — AL2023 + Node 22

Checklist não destrutivo (migração manual):

```bash
./scripts/aws-fleet/deploy-qdbback-ec2.sh --phase al2023
```

Passos resumidos:

1. AMI/snapshot da instância atual
2. Nova instância Amazon Linux 2023 ARM64 (mesmo SG)
3. Copiar `/home/ec2-user`, `database.sqlite`, `/etc/qdbback/monitor.env`
4. `nvm install 22` + `npm ci --omit=dev`
5. `./deploy-qdbback-ec2.sh --phase systemd && --phase start`
6. Smoke: honeypot 80/443, monitor :3500, Node Fleet card, `/internal/metrics`
