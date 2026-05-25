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

- **Node 22 LTS** na EC2 (`deploy --phase node22`)
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

- TLS Let's Encrypt (requer domínio apontando para a EC2)
- Métricas Prometheus nativas no qdbback
