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
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/          # 301
curl -sk -o /dev/null -w '%{http_code}\n' https://127.0.0.1:3443/       # 200
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
curl -sk -o /dev/null -w '%{http_code}\n' https://3.236.249.77:3443/
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

## Fase 5 — Modernização (futuro)

Node 22, classificação de bots, Prometheus, auth admin robusto.
