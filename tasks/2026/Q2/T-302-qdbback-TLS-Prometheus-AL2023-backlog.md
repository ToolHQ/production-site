# T-302: qdbback — TLS Let's Encrypt, Prometheus e AL2023

- **Status**: In Progress
- **Priority**: 🔵 Medium
- **Owner**: Cursor / AI Radar
- **Epic**: qdbback / External Fleet (follow-up T-296)
- **Est**: 2d

## Context

Backlog pós **T-296** na EC2 `aws-ec2-fleet-01` (`3.236.249.77`, AL2, Node 16.20.2):

1. **Prometheus** — exposição nativa para scrape OCI (allowlist IPs K8s).
2. **Let's Encrypt** — substituir cert self-signed; requer DNS `honeypot.dnor.io` → IP EC2.
3. **AL2023 + Node 22+** — migração de SO (AL2 EOL); preparar runbook + fase deploy.

## Tasks

### Fase A — Prometheus `/internal/metrics`

- [x] Handler text/plain exposition format (counter/gauge honeypot)
- [x] Rota allowlist OCI em `mainRouter`
- [x] Testes unitários handler
- [ ] Deploy sync + validação curl from OCI egress IP

### Fase B — Let's Encrypt

- [x] Documentar DNS `honeypot.dnor.io` → `3.236.249.77`
- [x] Fase `letsencrypt` em `deploy-qdbback-ec2.sh` (certbot standalone)
- [ ] Criar DNS A record (operador)
- [ ] Executar `--phase letsencrypt` + validar HTTPS confiável
- [ ] Atualizar `registry.yaml` / rs-observability scrape host (se migrar de IP)

### Fase C — AL2023

- [x] Runbook migração AL2 → AL2023 (Fase 6 runbook)
- [x] Fase `al2023` no deploy script (checklist, não destrutivo)
- [ ] Executar migração EC2 + smoke pós-migração

## Validação

```bash
# Prometheus (após deploy)
curl -sk https://3.236.249.77/internal/metrics  # 403 off-cluster
ssh oci-k8s-node-1 'curl -sk https://3.236.249.77/internal/metrics | head'

# Let's Encrypt (após DNS)
curl -sI https://honeypot.dnor.io/ | grep -i issuer

# Node Fleet
curl -s https://reports.dnor.io/api/live/overview | jq .honeypot.available
```
