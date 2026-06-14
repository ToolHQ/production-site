# Scripts SSDNodes — CI Platform (T-341)

Scripts operacionais para Jenkins + SonarQube no cluster `ssdnodes-6a12f10c9ef11`.

## Fluxo completo (ordem)

| # | Script | O que faz |
|---|--------|-----------|
| 1 | [configure_ssdnodes_ci_dns_godaddy.sh](configure_ssdnodes_ci_dns_godaddy.sh) | Registros A `sonar` + `jenkins` → 104.225.218.78 (GoDaddy API) |
| 2 | [create_sonar_ci_secrets.sh](create_sonar_ci_secrets.sh) | YAML Secrets Postgres + monitoring passcode → `kubectl apply` |
| 3 | [deploy_ssdnodes_components.sh](../ssdnodes/deploy_ssdnodes_components.sh) | Helm: Postgres → Sonar → Jenkins + ingress + NetworkPolicy + TLS |
| 4 | [export_ci_credentials.sh](export_ci_credentials.sh) | Gera `~/ssdnodes-ci-platform-credentials.txt` (chmod 600) |
| 5 | [setup_jenkins_ci_jobs.sh](setup_jenkins_ci_jobs.sh) | Job multibranch + credenciais Sonar/GitHub + scan |
| 6 | [validate_ssdnodes_ci.sh](../../../scripts/harness/validate_ssdnodes_ci.sh) | Smoke HTTPS + pods Running |

## Referência rápida

### configure_ssdnodes_ci_dns_godaddy.sh

```bash
source ~/production-site-cursor/.env.godaddy   # GODADDY_API_KEY/SECRET
bash oci-k8s-cluster/scripts/ssdnodes/configure_ssdnodes_ci_dns_godaddy.sh
bash oci-k8s-cluster/scripts/ssdnodes/configure_ssdnodes_ci_dns_godaddy.sh --dry-run
```

### create_sonar_ci_secrets.sh

Imprime YAML (nunca commitar valores). Cria secrets em `sonarqube-db` **e** `sonarqube` (JDBC).

```bash
bash oci-k8s-cluster/scripts/ssdnodes/create_sonar_ci_secrets.sh \
  --postgres-password "$(openssl rand -base64 24)" \
  | ssh ssdnodes-6a12f10c9ef11 kubectl apply -f -
```

### deploy_ssdnodes_components.sh

Chamado pela TUI (Hardening 15–17) ou direto:

```bash
bash oci-k8s-cluster/scripts/ssdnodes/deploy_ssdnodes_components.sh ci-platform
bash oci-k8s-cluster/scripts/ssdnodes/deploy_ssdnodes_components.sh ci-status
```

Targets: `sonarqube`, `jenkins`, `ci-platform`, `ci-status`, `dashboard`, `kubecost`, `all`, `status`.

### export_ci_credentials.sh

```bash
bash oci-k8s-cluster/scripts/ssdnodes/export_ci_credentials.sh
# --output ~/outro-arquivo.txt
```

Lê secrets do cluster via SSH + kubectl. **Atualize manualmente** a senha Sonar após primeiro login.

### setup_jenkins_ci_jobs.sh + seed_jenkins_ci_job.sh

```bash
gh auth login
bash oci-k8s-cluster/scripts/ssdnodes/setup_jenkins_ci_jobs.sh --update-home-creds
bash oci-k8s-cluster/scripts/ssdnodes/seed_jenkins_ci_job.sh
```

| Script | Função |
|--------|--------|
| `setup_jenkins_ci_jobs.sh` | Secret K8s + helm JCasC (sonar-token, github-pat, Sonar server) |
| `seed_jenkins_ci_job.sh` | Job multibranch `production-site` via Groovy no pod |

Variáveis: `SONAR_ADMIN_PASSWORD`, `SONAR_TOKEN`, `GITHUB_TOKEN`, `JENKINS_JOB_NAME`.

## Segurança

- Tokens **nunca** no Git — `.gitignore`: `.env.godaddy`, `ssdnodes-ci-platform-credentials.txt`
- UFW: porta 80 global só durante emissão TLS; `cert-renew-ufw.timer` para renovação
- NetworkPolicies: Postgres interno; Sonar/Jenkins só via ingress-nginx

## Ver também

- [components/ssdnodes/jenkins/README.md](../../../components/ssdnodes/jenkins/README.md)
- [components/ssdnodes/README.md](../../../components/ssdnodes/README.md)
- [tools/citools/README.md](../../../tools/citools/README.md)
