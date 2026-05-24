# qdbback — Análise AS-IS (2026-05-24)

Recuperação da EC2 `aws-ec2-fleet-01` (`3.236.249.77`, `t4g.micro`, ARM64, us-east-1).

## Propósito

Honeypot/logger HTTP: persiste cada requisição recebida em SQLite, com dashboard admin para pesquisa de bots e exploits.

## Layout em produção (EC2)

```
/home/ec2-user/
├── database.sqlite       # ~359 MiB — NÃO versionado
├── private.key           # TLS — NÃO versionar
├── certificate.crt
├── version.json
└── server/               # = apps/qdbback no repo
    ├── routers/          # rotas (obrigatório — index.js importa daqui)
    ├── services/         # fs, dns, encoding, etc.
    ├── handlers/
    └── index.js
```

> **Repo:** `apps/qdbback/` deve manter `routers/` e `services/`. `version.json` fica em `apps/version.json` (path `../version.json` desde `server/`).

## Arquitetura de rede

| Porta | Protocolo (prod) | Função |
|-------|------------------|--------|
| 80 | HTTP | Redirect 301 → HTTPS (prod; dev: 3000) |
| 443 | HTTPS | Site público honeypot (prod; dev: 3443) |
| 3500 | **HTTPS** | Admin/monitor (não HTTP) |
| 9100 | HTTP | node_exporter (fleet) |

`isProduction = hostname.endsWith('.ec2.internal')`

### Auth admin (`:3500`)

1. Primeiro acesso: `?key=palmeirasnaotemmundial` → cookie `monitor-key=215eaf6a-74c4-42cf-8417-b8f395bfeea6`
2. Sem cookie → 404 em todas as rotas admin
3. `POST /api/monitor/sql` executa SQL arbitrário (com cookie)

**Tunnel local (recomendado):**

```bash
ssh -L 3500:127.0.0.1:3500 aws-ec2-fleet-01
# https://localhost:3500/monitor?key=palmeirasnaotemmundial  (-k no browser)
```

## Persistência SQLite

### Schema `httpRequests`

`timestamp`, `method`, `path`, `timeElapsed`, `remoteIp`, `remoteHostname`, `statusCode`, `userAgent`, `headers` (JSON), `body`, `country`, `classification`

Insert no `res.on('finish')` — **exceto `127.0.0.1`**.

### Inventário histórico

| Métrica | Valor |
|---------|-------|
| Período | 2020-11-22 → 2021-11-17 |
| `httpRequests` | 82.992 |
| `applicationLogs` | 1.249.390 |
| IPs únicos | 12.303 |
| `country` / `classification` preenchidos | **0** (feature nunca implementada) |

### Status codes

| Code | Count |
|------|-------|
| 301 | 55.179 |
| 404 | 15.142 |
| 200 | 12.166 |

### Top paths (scanner traffic)

| Path | Hits |
|------|------|
| `/` | 30.818 |
| `/.env` | 8.438 |
| PHPUnit RCE | 2.474 |
| `/phpmyadmin/` | 1.629 |
| `/boaform/admin/formLogin` | 1.078 |

### Categorias heurísticas

| Categoria | ~Hits |
|-----------|-------|
| `.env` | 10.510 |
| PHPUnit | 4.160 |
| phpMyAdmin | 2.655 |
| WordPress | 2.428 |
| Admin panels | 5.176 |

### Tráfego mensal (2021)

~6–8k requests/mês estável.

## Stack

- Node **16.6.0** (nvm), ES modules
- sqlite3 5.0.2 (binding nativo ARM64)
- webpack 5 + Material Components (admin UI)
- PM2 legado (substituído por systemd na reativação)

## Problemas identificados (pré-reativação)

1. TLS expirado (CN `52.20.74.125`, set/2021)
2. Webpack roda em **todo** boot (~14s) mesmo com `dist/` presente
3. SG AWS: apenas `:22` e `:9100` abertos
4. Admin SQL arbitrário — nunca expor `:3500` publicamente
5. Disco EC2 ~73% usado
6. `apps/qdbback/` estava sem `routers/`/`services/` (corrigido na Fase 0)

## Smoke test (2026-05-24)

Na EC2 com Node 16.6 + código intacto:

- Boot ~14,5s, RSS ~49 MB
- `:80` → 301, `:443` → 200, `:3500` HTTPS + cookie → 200 + API JSON

## Fases de reativação

Ver `docs/REACTIVATION-RUNBOOK.md` e scripts em `scripts/aws-fleet/deploy-qdbback-ec2.sh`.
