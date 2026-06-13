# SSDNodes Components

Workloads para o cluster K8s do servidor SSDNodes (x86_64, 12 vCPU / 60 GB RAM / 1.1 TB disk).

**Kubeconfig**: `~/.kube/ssdnodes.yaml`  
**IP público**: `104.225.218.78`  
**Hostname Canônico (SSH)**: `ssdnodes-6a12f10c9ef11` (alias configurado em `~/.ssh/config`)

SSH (T-331):

```bash
bash oci-k8s-cluster/scripts/ssdnodes/install_ssdnodes_ssh_config.sh
ssh ssdnodes-6a12f10c9ef11 hostname -f
```

Alias legado `ssdnodes-monstro` permanece no snippet apenas para compatibilidade.

**UFW (posture hardened — `ufw_manager.sh --apply`):**

| Porta | Exposição |
|-------|-----------|
| 22/tcp | Mundo (safety net) + fail2ban recomendado |
| 80/443 | ADMIN + INGRESS IPs + Tailscale `100.64.0.0/10` |
| 443 | GitHub webhook CIDRs (`github-webhook-ip-ranges.txt`) → Jenkins `/github-webhook/` (T-345) |
| 6443 | ADMIN only |
| 9100 | IPs OCI (Prometheus scrape) |
| 8443 | ADMIN + INGRESS + Tailscale (fleet-ops-gateway) |
| 11434 | **Deny** (Ollama localhost only) |

Portas K8s internas (8472, 10250–10252, 2379–2380) **não** são abertas externamente no posture hardened.

**Fleet Copilot:** ver [FLEET-COPILOT-SECURITY-PREREQS.md](FLEET-COPILOT-SECURITY-PREREQS.md)

## Componentes

| Componente               | Namespace            | Quando instalar                        |
| ------------------------ | -------------------- | -------------------------------------- |
| `local-path-provisioner` | `local-path-storage` | Pré-requisito para qualquer PVC        |
| `nginx-ingress`          | `ingress-nginx`      | Pré-requisito para Ingress HTTP/HTTPS  |
| `minio`                  | `minio`              | Object storage S3-compatible (500 GiB) |

## Deploy

```bash
export KUBECONFIG=~/.kube/ssdnodes.yaml

# 1. Storage class (local-path)
kubectl apply -f components/ssdnodes/local-path-provisioner.yaml

# 2. nginx-ingress via Helm (hostNetwork para portas 80/443)
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  -f components/ssdnodes/nginx-ingress-values.yaml \
  --wait

# 3. cert-manager (TLS via Let's Encrypt)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.3/cert-manager.yaml
kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=90s
kubectl apply -f components/ssdnodes/cluster-issuer.yaml

# 4. MinIO via Helm
helm repo add minio https://charts.min.io/
helm repo update
helm upgrade --install minio minio/minio \
  --namespace minio --create-namespace \
  -f components/ssdnodes/minio-values.yaml \
  --wait

# 5. Ingresses com TLS
kubectl apply -f components/ssdnodes/minio-ingress.yaml
```

## DNS

Para usar os Ingresses, apontar subdomínios para `104.225.218.78`:

- `minio.ssdnodes.dnor.io` → console MinIO
- `s3.ssdnodes.dnor.io` → API S3 MinIO
- `k8s.ssdnodes.dnor.io` → Kubernetes Dashboard
- `cost.ssdnodes.dnor.io` → Kubecost
- `sonar.ssdnodes.dnor.io` → SonarQube CE (T-341)
- `jenkins.ssdnodes.dnor.io` → Jenkins LTS (T-341)
- `n8n.ssdnodes.dnor.io` → n8n automation (T-361)

## n8n (T-361)

Ver [n8n/README.md](n8n/README.md) — deploy, upgrade, backup.

```bash
source .env.godaddy
bash oci-k8s-cluster/scripts/ssdnodes/configure_ssdnodes_n8n_dns_godaddy.sh
bash oci-k8s-cluster/scripts/ssdnodes/create_n8n_secret.sh \
  | ssh ssdnodes-6a12f10c9ef11 kubectl apply -f - 2> ~/ssdnodes-n8n-credentials.txt
bash oci-k8s-cluster/scripts/ssdnodes/deploy_ssdnodes_components.sh n8n
bash scripts/harness/validate_ssdnodes_n8n.sh
```

## CI Platform (T-341)

ADR: [ADR-jenkins-sonarqube-colocation.md](ADR-jenkins-sonarqube-colocation.md)

**Zero custo variável** — SonarQube Community + Jenkins self-hosted; PostgreSQL interno (ClusterIP).

### Pré-requisitos

1. DNS `sonar` + `jenkins` → `104.225.218.78` (GoDaddy API):

```bash
source .env.godaddy
bash oci-k8s-cluster/scripts/ssdnodes/configure_ssdnodes_ci_dns_godaddy.sh
```

2. Secrets (nunca no Git):

```bash
bash oci-k8s-cluster/scripts/ssdnodes/create_sonar_ci_secrets.sh \
  --postgres-password "$(openssl rand -base64 24)" \
  | ssh ssdnodes-6a12f10c9ef11 kubectl apply -f -
```

3. Credenciais locais (após deploy):

```bash
bash oci-k8s-cluster/scripts/ssdnodes/export_ci_credentials.sh
# → ~/ssdnodes-ci-platform-credentials.txt (chmod 600)
```

4. Job Jenkins multibranch + tokens:

```bash
bash oci-k8s-cluster/scripts/ssdnodes/setup_jenkins_ci_jobs.sh --update-home-creds
```

Documentação scripts: [oci-k8s-cluster/scripts/ssdnodes/README.md](../../oci-k8s-cluster/scripts/ssdnodes/README.md)

### Deploy

```bash
# TUI: Node Hardening → 15/16/17
bash oci-k8s-cluster/scripts/ssdnodes/deploy_ssdnodes_components.sh ci-platform
bash oci-k8s-cluster/scripts/ssdnodes/deploy_ssdnodes_components.sh ci-status
bash scripts/harness/validate_ssdnodes_ci.sh
```

### citools + Jenkins genérico (T-341 fase 2)

ADR: [ADR-citools-harness-evolution.md](ADR-citools-harness-evolution.md)

Jenkins **não** codifica stages em Groovy — delega ao CLI Rust:

```bash
cd tools/citools && cargo build --release
citools run-all --pipeline components/ssdnodes/jenkins/pipeline.yaml
```

- Pipeline declarativo: [jenkins/pipeline.yaml](jenkins/pipeline.yaml)
- Jenkinsfile genérico: [jenkins/Jenkinsfile.generic](jenkins/Jenkinsfile.generic)

**Não** usar `oci-k8s-cluster/deploy_components.sh` para `ssdnodes` — guardrail T-341 bloqueia deploy no master OCI.
