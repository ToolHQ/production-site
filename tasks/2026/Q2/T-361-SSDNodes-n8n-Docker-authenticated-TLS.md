# T-361: SSDNodes — n8n self-hosted Docker (latest, auth, TLS, domínio)

- **Status**: Done
- **Priority**: 🔼 High
- **Owner**: Cursor / AI Radar
- **Epic**: SSDNodes Automation / n8n
- **Est**: 1d
- **Criado**: 2026-06-09
- **Blocks**: [T-362](T-362-n8n-email-AI-classification-research-spec.md)

## Context

Precisamos de uma instância **n8n Community (free/self-hosted)** no SSDNodes para automações futuras — começando pelo pipeline de email (T-362).

Padrão já estabelecido no SSDNodes (`jenkins.ssdnodes.dnor.io`, `minio.ssdnodes.dnor.io`):

- **nginx-ingress** + **cert-manager** (`letsencrypt-prod`)
- DNS `*.ssdnodes.dnor.io` → IP do host
- UFW deny-by-default; apenas 22/80/443
- Secrets fora do Git; manifests em `components/ssdnodes/`

### Alvo

| Item | Valor |
|------|-------|
| Domínio | `n8n.ssdnodes.dnor.io` (confirmar disponibilidade DNS) |
| Runtime | Docker (Compose no host **ou** Deployment K8s — ADR na implementação) |
| Imagem | `docker.n8n.io/n8nio/n8n` — tag **latest estável** com pin semver no IaC + doc de bump |
| Auth | Owner account + `N8N_BASIC_AUTH` ou user management nativo; **sem** instância pública anônima |
| Dados | Volume persistente (PVC Longhorn/local-path **ou** bind mount host) |
| DB | SQLite embutido (MVP) — Postgres dedicado fica para T-362 |
| Atualização | Script/runbook de pull + restart + smoke |

### Restrições

- Zero custo variável (sem n8n Cloud)
- Não expor webhooks sem TLS
- Ollama permanece `127.0.0.1:11434` — n8n acessa via host network ou sidecar local, nunca público

## Tasks

- [x] ADR curto: Docker Compose no host vs Pod K8s (recomendação com RAM/CPU do monstro)
- [x] DNS A record `n8n.ssdnodes.dnor.io` (GoDaddy — 2026-06-09)
- [x] IaC: `components/ssdnodes/n8n-k8s.yaml` + ingress + PVC
- [x] Secret: `N8N_ENCRYPTION_KEY`, basic auth (`create_n8n_secret.sh`)
- [x] Ingress TLS (`letsencrypt-prod`) — cert READY após retry UFW:80
- [x] UFW: porta 80 temporária só para ACME; n8n ClusterIP (sem bind público)
- [x] Health/smoke: `validate_ssdnodes_n8n.sh` PASS
- [x] Runbook: `components/ssdnodes/n8n/README.md`
- [x] README link em `components/ssdnodes/README.md`

## Acceptance

- UI acessível em `https://n8n.ssdnodes.dnor.io` com certificado válido
- Login obrigatório; sem acesso anônimo a workflows
- Workflow de teste (manual trigger) executa com sucesso
- Documentação de deploy e upgrade no repo
