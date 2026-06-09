# ADR: n8n runtime no SSDNodes (T-361)

## Contexto

Automações futuras (T-362 email + Ollama) precisam de n8n self-hosted com TLS e auth. SSDNodes já opera Jenkins, Sonar, MinIO via **K8s + nginx-ingress + cert-manager**.

## Decisão

**Deployment K8s** (não Docker Compose no host).

| Critério | K8s | Compose host |
|----------|-----|--------------|
| Padrão existente | ✅ Jenkins/Sonar/MinIO | ❌ exceção |
| TLS/Ingress | ✅ reutiliza cert-manager | manual NPM |
| Backup PVC | local-path snapshot | bind mount manual |
| RAM headroom | ~52 GiB livres; n8n MVP ~512Mi–1Gi | competiria com Ollama host |
| Ollama (T-362) | host `127.0.0.1:11434` via `host.docker.internal` ou IP nó | mais simples |

**DB MVP:** SQLite em PVC (`/home/node/.n8n`) — Postgres dedicado fica para T-362.

**Auth:** Basic Auth (`N8N_BASIC_AUTH_*`) + user management nativo no primeiro login (owner). Sem instância anônima.

**Imagem:** `docker.n8n.io/n8nio/n8n:1.97.1` (pin semver; bump via `n8n-k8s.yaml` + rollout).

## Consequências

- Namespace `n8n`, PVC 10Gi, ClusterIP:5678, Ingress `n8n.ssdnodes.dnor.io`
- Secrets gerados por `create_n8n_secret.sh` (nunca no Git)
- Ollama: workflows T-362 usarão `http://104.225.218.78:11434` **negado** — acesso via `hostNetwork` sidecar ou HTTP proxy interno (spec T-362)
