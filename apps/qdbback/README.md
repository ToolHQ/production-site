# qdbback — HTTP Request Logger & Bot Research Honeypot

Recuperado da EC2 `aws-ec2-fleet-01` (`3.236.249.77`, `t4g.micro`, us-east-1) em **2026-05-24**.

Projeto original: **`@dnorio/qdbback`** ("Question DB") — servidor Node.js que **persiste cada requisição HTTP** recebida em SQLite, com dashboard de monitoramento (Material Components + Chart.js + webpack).

## Objetivo de pesquisa (2026+)

Reativar esta stack na EC2 AWS do Node Fleet como **sensor de tráfego malicioso**:

- AWS é alvo frequente de scanners/exploits
- Classificar bots, paths de exploit (`.env`, PHPUnit RCE, WordPress, etc.)
- Correlacionar com métricas do Node Fleet (`reports.dnor.io`)

## Arquitetura (como funcionava)

```
Internet → :80 HTTP / :443 HTTPS (prod EC2)
              │
              ▼
         index.js (createServer)
              │
              ▼
         router.js ── on response finish ──► INSERT httpRequests (SQLite)
              │
              ├── routers/productionHttpRouter (redirect HTTP)
              ├── routers/mainRouter (site público HTTPS)
              └── routers/monitoringRouter :3500 HTTPS (admin UI + API)
```

> **Layout:** `index.js` importa de `routers/` e `services/` — não use cópias legadas na raiz.

### Portas (`config.js`)

| Porta | Protocolo (prod EC2) | Dev local | Função |
|-------|----------------------|-----------|--------|
| 80 | HTTP | 3000 | Redirect 301 → HTTPS |
| 443 | HTTPS | 3443 | Site público (honeypot) |
| 3500 | HTTPS | 3500 | Admin / monitoring dashboard |
| 9100 | HTTP | — | node_exporter (Node Fleet) |

Em produção (`*.ec2.internal`), bind em **80/443** via `CAP_NET_BIND_SERVICE` no systemd.

### Auth admin (`:3500` em produção)

## Monitor admin (`:3500`)

Auth via env (Fase 5c) — arquivo `/etc/qdbback/monitor.env` na EC2:

1. `QDBBACK_MONITOR_SECRET` — deriva cookie `monitor-key`
2. `QDBBACK_MONITOR_LOGIN_KEY` — query `?key=` para login (8h cookie)

Dev local (sem env): `?key=palmeirasnaotemmundial` (legado).

`/api/monitor/sql` em produção: **somente SELECT read-only**.
3. Sem cookie → **404** em todas as rotas admin

**Tunnel SSH (recomendado — não exponha :3500 publicamente):**

```bash
ssh -L 3500:127.0.0.1:3500 aws-ec2-fleet-01
# https://localhost:3500/monitor?key=palmeirasnaotemmundial
```

### Persistência (`sqlite3.js` + `router.js`)

Tabela **`httpRequests`**:

- `timestamp`, `method`, `path`, `timeElapsed`
- `remoteIp`, `remoteHostname`, `statusCode`, `userAgent`
- `headers` (JSON), `body`, `country`, `classification`

Insert no evento `res.on('finish')` — exceto requests de `127.0.0.1`.

Outras tabelas: `applicationLogs`, `coolQueries`.

### UI de monitoramento

- Assets em `assets/monitor/` (SCSS → webpack → `dist/monitor/`)
- API paginada em `handlers/monitoringHandlers.js`
- Queries SQL validadas por schema (`monitoringSchemas.js`)

## Dados históricos (backup)

| Métrica | Valor |
|---------|-------|
| Período | 2020-11-22 → 2021-11-17 |
| `httpRequests` | 82.992 |
| `applicationLogs` | ~1.249.340 |
| DB size | ~359 MiB |

Backup completo: `archive/aws-ec2-fleet-01/recovery-2026-05-24/` (local, gitignored).

## Stack original

- Node **16.6.0** (nvm)
- PM2 (`ecosystem.config.js`)
- ES modules (`"type": "module"`)
- sqlite3 5.0.2, webpack 5, Material Components Web 8–10

## Rodar localmente (dev)

```bash
cd apps/qdbback
npm ci
# database.sqlite: copiar do archive para apps/qdbback/../ (path ../database.sqlite)
# version.json: já em apps/version.json
node app.js
```

## Reativação na EC2

Ver [`docs/REACTIVATION-RUNBOOK.md`](docs/REACTIVATION-RUNBOOK.md) e [`docs/AS-IS-ANALYSIS.md`](docs/AS-IS-ANALYSIS.md).

```bash
./scripts/aws-fleet/deploy-qdbback-ec2.sh --phase all
./scripts/aws-fleet/configure-qdbback-sg.sh --apply
./scripts/aws-fleet/validate-qdbback-logging.sh
```

## Próximos passos (modernização — não implementado)

1. Node 22 LTS + dependências atualizadas
2. Substituir sqlite3 nativo por `better-sqlite3` ou manter com build ARM64
3. Classificação automática de bots/exploits (rules + ML leve)
4. Export Prometheus metrics / integração AI Radar
5. Deploy containerizado na EC2 com systemd (substituir PM2/nohup)
6. **Nunca** commitar TLS private keys — usar secrets/Parameter Store

## Origem

- GitLab histórico: `gitlab.com/dnorio/back`
- Commit ref no backup: `b144167f` (`version.json`)
