# Migração qdbback — Amazon Linux 2 → AL2023 + Node 22

**T-302 Fase C** — procedimento manual (não destrutivo via deploy automático).

## Pré-requisitos

- Snapshot/AMI da instância `i-0e8ca7a9b50e474a9` antes de qualquer alteração
- Janela de manutenção (~30–60 min downtime honeypot)
- Acesso SSH + AWS console (SG, instância)

## Checklist

### 1. Backup

```bash
ssh aws-ec2-fleet-01 'sudo systemctl stop qdbback.service'
ssh aws-ec2-fleet-01 'tar czf ~/qdbback-backup-$(date +%F).tar.gz \
  /home/ec2-user/server /home/ec2-user/database.sqlite /etc/qdbback/monitor.env 2>/dev/null || true'
```

Criar **AMI** ou snapshot EBS no console AWS.

### 2. Nova instância AL2023 ARM64

- AMI: **Amazon Linux 2023** (aarch64)
- Tipo: `t4g.micro` (ou igual)
- Mesmo VPC/SG (portas 80/443/3500 conforme `configure-qdbback-sg.sh`)
- **Elastic IP:** recomendado — evita reconfigurar DNS `honeypot.dnor.io` após replace

### 3. Restaurar dados

```bash
# Na nova instância (ec2-user)
rsync -av aws-ec2-fleet-01-old:/home/ec2-user/ /home/ec2-user/
sudo mkdir -p /etc/qdbback
sudo cp monitor.env.backup /etc/qdbback/monitor.env  # do backup
```

### 4. Node.js 22 + deps

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.nvm/nvm.sh
nvm install 22
nvm alias default 22
cd ~/server && npm ci --omit=dev
```

### 5. Deploy systemd

```bash
# Do repo local
./scripts/aws-fleet/deploy-qdbback-ec2.sh --phase systemd --ssh-alias NOVO_ALIAS
./scripts/aws-fleet/deploy-qdbback-ec2.sh --phase start --ssh-alias NOVO_ALIAS
```

Ajustar `ExecStart` no deploy script para Node 22 quando AL2023 for padrão.

### 6. Smoke

```bash
./scripts/aws-fleet/validate-qdbback-logging.sh
./scripts/aws-fleet/validate-qdbback-metrics.sh
curl -s https://reports.dnor.io/api/live/overview | jq .honeypot.available
```

### 7. Cutover DNS (se IP mudou)

Atualizar A record `honeypot.dnor.io` → novo IP; rerun `--phase letsencrypt` se TLS ativo.

## Rollback

Restaurar AMI/snapshot anterior ou reassociar Elastic IP à instância antiga.
