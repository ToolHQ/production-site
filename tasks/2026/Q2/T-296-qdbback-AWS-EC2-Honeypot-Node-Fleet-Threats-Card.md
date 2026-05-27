# T-296: qdbback AWS EC2 — Honeypot reativação + Node Fleet threats card

- **Status**: Done
- **Priority**: 🔼 High
- **Owner**: Cursor / AI Radar
- **Epic**: External Fleet / Cluster Pulse / qdbback honeypot
- **Est**: 3d

## Context

Reativar o honeypot legado **qdbback** na EC2 `aws-ec2-fleet-01` (`3.236.249.77`, ARM64, Amazon Linux 2) para captura de tráfego malicioso em SQLite, integrar o nó ao **Node Fleet** em `reports.dnor.io`, e expor métricas de threats no dashboard executivo (card laranja 🍯).

Duas UIs distintas:

| UI | Onde | Público |
|----|------|---------|
| **Monitor admin** (forense) | `https://3.236.249.77:3500/monitor` | Ops — grid Material, SQL read-only |
| **Card honeypot** (executivo) | `https://reports.dnor.io` → Node Fleet | Visão agregada total/24h/top tags |

## Entregas por fase

### Fases 0–4 — Reativação (PRs #319–#322)

- [x] Repo `apps/qdbback/` + runbook AS-IS
- [x] EC2 systemd, honeypot 80/443, SG, logging E2E
- [x] Scripts `deploy-qdbback-ec2.sh`, `validate-qdbback-logging.sh`

### Fase 5a — Classificação heurística (PR #323)

- [x] `services/classifyRequest.js` → coluna `classification`
- [x] `GET /api/monitor/threats` (admin `:3500`)

### Fase 5b — Node Fleet card (PR #324)

- [x] `GET /internal/threats-summary` (qdbback `:443`, allowlist IPs OCI)
- [x] `registry.yaml` → `honeypot: true` em `aws-ec2-fleet-01`
- [x] `rs-observability-api` → campo `.honeypot` em `/api/live/overview`
- [x] UI `NodesPanel.tsx` → card `.honeypot-card`

### Fase 5c — Modernização ops (PRs #326–#328)

- [x] Auth admin via `/etc/qdbback/monitor.env`
- [x] GeoIP `country` (`geoip-lite`)
- [x] SQL guard — só `SELECT` read-only em prod
- [x] Node 16.20.2 (AL2; Node 22+ exige AL2023)
- [x] Logrotate + timer purge `applicationLogs`

## Endpoints (mapa)

### Honeypot público (captura)

| Endpoint | Porta | Auth |
|----------|-------|------|
| `GET /` (pudim) | 443 | nenhuma |
| `GET /.env`, probes diversos | 443 | nenhuma (logados) |

### Monitor admin (forense)

| Endpoint | Porta | Auth |
|----------|-------|------|
| `GET /monitor?key=…` | 3500 | login key → cookie 8h |
| `GET /api/monitor/requests` | 3500 | cookie |
| `GET /api/monitor/threats` | 3500 | cookie |
| `POST /api/monitor/sql` | 3500 | cookie + SELECT only |

### Node Fleet (dashboard)

| Endpoint | Onde | Auth |
|----------|------|------|
| `GET /api/live/overview` → `.honeypot` | `reports.dnor.io` | ingress público |
| scrape interno | `https://3.236.249.77/internal/threats-summary` | allowlist OCI |
| Prometheus | `https://3.236.249.77/internal/metrics` | allowlist OCI |

## Critérios de aceite

- [x] Probe externo incrementa `httpRequests` com `classification` e `country`
- [x] Card honeypot visível em `reports.dnor.io` com total/24h/top tags
- [x] Monitor admin acessível com key de `monitor.env`
- [x] `qdbback.service` active; 80/443/3500 operacionais

## Evidência live (2026-05-25)

- EC2: `qdbback.service` **active** — HTTP 301 / HTTPS 200
- GeoIP: `150.136.67.52 → US`, `189.62.149.233 → BR`
- API: `curl -s https://reports.dnor.io/api/live/overview | jq .honeypot.available` → `true`
- Login admin: `QDBBACK_MONITOR_LOGIN_KEY` em `/etc/qdbback/monitor.env`

## PRs

- #319–#322 reativação · #323 classificação · #324 Node Fleet · #326–#328 ops 5c

## Pendente (backlog futuro)

- [ ] TLS Let's Encrypt (`honeypot.dnor.io`; `./deploy-qdbback-ec2.sh --phase letsencrypt`)
- [ ] Migração Amazon Linux 2023 → Node 22+ (runbook Fase 6)
- [x] Métricas Prometheus nativas — `GET /internal/metrics`
- [x] Sincronizar `apps/qdbback/deploy/qdbback.service` com unit live do deploy script

## Tasks

- [x] Fases 0–5c implementadas e deployadas na EC2
- [x] Card honeypot validado em reports.dnor.io
- [x] Documentação runbook + este T-ID
