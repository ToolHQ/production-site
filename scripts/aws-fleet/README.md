# AWS Fleet — automação de nós externos

Provisiona instâncias AWS/EC2 (ou similares) com bootstrap seguro e integração automática ao **Node Fleet** (`reports.dnor.io`).

## Arquitetura

```
config/external-fleet/registry.yaml   ← fonte de verdade
        │
        ▼
generate_fleet_artifacts.py
        ├── components/observability/external-fleet/generated/*-exporter.yaml
        ├── apps/rs-observability-api/config/external_nodes.json
        ├── oci-k8s-cluster/common.sh (EXTERNAL_NODES)
        ├── scripts/harness/validate_rs_observability_live.sh
        └── web-v2/src/generated/cluster-badges.css

provision-aws-external-node.sh
        ├── remote-bootstrap.sh (via SSH na instância)
        ├── chave ~/.ssh/aws-fleet-<name>.ed25519
        └── registry + generate + (opcional) kubectl apply
```

## qdbback (honeypot HTTP logger)

Reativação do app legado na EC2 `aws-ec2-fleet-01`:

```bash
./scripts/aws-fleet/deploy-qdbback-ec2.sh --phase all
./scripts/aws-fleet/configure-qdbback-sg.sh --apply   # requer: aws sso login
./scripts/aws-fleet/validate-qdbback-logging.sh
```

Docs: `apps/qdbback/docs/AS-IS-ANALYSIS.md`

---

- `python3` + `PyYAML` (`pip install pyyaml`)
- `ssh`, `scp`, `curl`
- Acesso SSH inicial à instância (root ou sudo) — Security Group `:22` liberado para seu IP
- `kubectl` + tunnel ativo (se usar `--apply`)

## Provisionar nova EC2

```bash
cd ~/production-site-cursor

# Dry-run (só mostra o plano)
./scripts/aws-fleet/provision-aws-external-node.sh \
  --host 3.236.249.77 \
  --instance-id i-0e8ca7a9b50e474a9 \
  --name aws-ec2-fleet-01 \
  --role dedicated \
  --ssh-user root \
  --dry-run

# Execução real + apply no cluster
./scripts/aws-fleet/provision-aws-external-node.sh \
  --host 3.236.249.77 \
  --instance-id i-0e8ca7a9b50e474a9 \
  --name aws-ec2-fleet-01 \
  --role dedicated \
  --ssh-user root \
  --apply
```

Depois:

```bash
cd apps/rs-observability-api && ./deploy.sh
curl -s https://reports.dnor.io/api/live/overview | jq '.nodes[] | select(.cluster=="AWS-EC2")'
```

## O que o bootstrap remoto faz (idempotente)

1. Cria usuário `dnorio-fleet` (configurável no registry)
2. Instala chave SSH **dedicada** (nunca commitada)
3. Instala `prometheus-node-exporter` na porta `9100`
4. Configura UFW: `:9100` só dos IPs OCI; `:22` só do IP do operador
5. Desabilita login root e autenticação por senha no sshd
6. Coleta metadados (CPU/RAM/disco + AWS instance-type/region)

## Security Group AWS (manual, obrigatório)

Além do UFW, configure no console AWS:

| Porta | Origem | Motivo |
|-------|--------|--------|
| 9100 | 4 IPs OCI (`150.136.x.x`) | Scrape Prometheus |
| 22 | Seu IP /32 | Ops |

**Nunca** abra `9100` ou `22` para `0.0.0.0/0`.

## Regenerar artefatos (sem provisionar)

```bash
./scripts/aws-fleet/generate_fleet_artifacts.py \
  --registry config/external-fleet/registry.yaml \
  --repo-root .
```

## Adicionar nó manualmente

Edite `config/external-fleet/registry.yaml` e rode o generator acima.

## Segredos

- Chaves ficam em `~/.ssh/aws-fleet-*.ed25519` (fora do Git)
- Não commitar `authorized_keys`, access keys AWS, nem senhas
