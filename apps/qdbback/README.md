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
Internet → :3000 HTTP / :3443 HTTPS
              │
              ▼
         index.js (createServer)
              │
              ▼
         router.js ── on response finish ──► INSERT httpRequests (SQLite)
              │
              ├── productionHttpRouter (rotas públicas mínimas)
              ├── mainRouter (dev)
              └── monitoringRouter :3500 (admin UI + API paginada)
```

### Portas (`config.js`)

| Porta | Função |
|-------|--------|
| 3000 | HTTP público |
| 3443 | HTTPS (certificados no diretório pai) |
| 3500 | Admin / monitoring dashboard |

`isProduction = hostname.endsWith('.ec2.internal')` — detecta EC2 automaticamente.

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
# Copiar database.sqlite do archive para apps/qdbback/ (ou path em sqlite3.js)
node app.js
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
