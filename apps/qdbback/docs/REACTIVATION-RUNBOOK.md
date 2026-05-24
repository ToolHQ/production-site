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

### 5b — Pendente

- Node 22 LTS, métricas Prometheus / Node Fleet
- Auth admin robusto, TLS Let's Encrypt
- GeoIP (`country`), logrotate
