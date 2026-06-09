# n8n — SSDNodes (T-361)

Self-hosted **n8n Community** em K8s no SSDNodes.

| Item | Valor |
|------|-------|
| URL | https://n8n.ssdnodes.dnor.io |
| Namespace | `n8n` |
| Imagem | `docker.n8n.io/n8nio/n8n:1.97.1` |
| Storage | PVC `n8n-data` 10Gi (`local-path`) |
| DB | SQLite (MVP) — Postgres em T-362 |

ADR: [ADR-n8n-runtime.md](ADR-n8n-runtime.md)

## Pré-requisitos

1. nginx-ingress + cert-manager (já no cluster)
2. DNS `n8n.ssdnodes.dnor.io` → `104.225.218.78`
3. Secret `n8n-credentials` (basic auth + encryption key)

## Deploy

```bash
# 1. DNS (GoDaddy)
source .env.godaddy
bash oci-k8s-cluster/scripts/ssdnodes/configure_ssdnodes_n8n_dns_godaddy.sh

# 2. Secret (salve stderr em arquivo local)
bash oci-k8s-cluster/scripts/ssdnodes/create_n8n_secret.sh \
  | ssh ssdnodes-6a12f10c9ef11 kubectl apply -f - \
  2> ~/ssdnodes-n8n-credentials.txt
chmod 600 ~/ssdnodes-n8n-credentials.txt

# 3. Manifests + Ingress + cert
bash oci-k8s-cluster/scripts/ssdnodes/deploy_ssdnodes_components.sh n8n

# 4. Smoke
bash scripts/harness/validate_ssdnodes_n8n.sh
```

## Primeiro acesso

1. Browser → `https://n8n.ssdnodes.dnor.io`
2. Basic Auth (credenciais em `~/ssdnodes-n8n-credentials.txt`)
3. Setup wizard → criar **owner account** (user management)

## Upgrade imagem

```bash
# Editar tag em components/ssdnodes/n8n-k8s.yaml
bash oci-k8s-cluster/scripts/ssdnodes/deploy_ssdnodes_components.sh n8n
# ou rollout:
ssh ssdnodes-6a12f10c9ef11 kubectl rollout restart deployment/n8n -n n8n
```

## Backup

```bash
ssh ssdnodes-6a12f10c9ef11 kubectl exec -n n8n deploy/n8n -- tar czf - /home/node/.n8n \
  > n8n-backup-$(date +%Y%m%d).tar.gz
```

## Rollback

```bash
# Reverter tag no n8n-k8s.yaml e redeploy, ou:
ssh ssdnodes-6a12f10c9ef11 kubectl rollout undo deployment/n8n -n n8n
```

## Ollama (T-362)

Ollama permanece `127.0.0.1:11434` no host. Workflows n8n → Ollama serão especificados em T-362 (HTTP interno, nunca exposto).
