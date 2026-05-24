# AWS EC2 Fleet-01 — Recovery Manifest

**Instance:** `i-0e8ca7a9b50e474a9` | **IP:** `3.236.249.77` | **Type:** `t4g.micro` ARM64  
**Recovery date:** 2026-05-24  
**Method:** `rsync` via `ssh aws-ec2-fleet-01`

## Local backup path

```
archive/aws-ec2-fleet-01/recovery-2026-05-24/
```

> **Git:** este diretório está **gitignored** (volume ~2GB com node_modules/nvm).  
> Fonte versionada da aplicação: `apps/qdbback/`.

## Arquivos críticos

| Arquivo | Descrição | Git |
|---------|-----------|-----|
| `database.sqlite` | 82k+ HTTP requests, ~359 MiB | local only |
| `private.key` / `certificate.crt` | TLS legado | **NUNCA commitar** |
| `server/` | Aplicação `@dnorio/qdbback` | → `apps/qdbback/` |
| `tools/` | Benchmark autocannon | referência |
| `benchdata/` | CSVs de benchmark 2020–2021 | local only |
| `nohup.out` | stdout do processo (~6 MiB) | local only |
| `52.20.74.125.zip` | artefato IP Elastic antigo | local only |

## Checksums

Ver `checksums.sha256` (database.sqlite).

## Repull

```bash
./scripts/aws-fleet/pull-ec2-backup.sh
```

## SQLite inventory (2026-05-24)

```json
{
  "httpRequests": 82992,
  "applicationLogs": 1249340,
  "period": { "from": "2020-11-22T21:40:08.845Z", "to": "2021-11-17T04:48:34.751Z" },
  "topPaths": ["/", "/.env", "/vendor/phpunit/...", "/phpmyadmin/", "/boaform/admin/formLogin"]
}
```
