# GitHub Actions — Migracao para Self-Hosted (Hetzner)

## Objetivo

Reduzir custo de GitHub Actions movendo execucao de CI para runner self-hosted no Hetzner.

## O que ja foi preparado no repo

- Workflows usam `CI_RUNNER_LABELS` com fallback seguro para `ubuntu-latest`:
  - `.github/workflows/quality-gates.yml`
  - `.github/workflows/auto-docs.yml`

Formato esperado de `CI_RUNNER_LABELS` em **Settings > Secrets and variables > Actions > Variables**:

```json
["self-hosted","linux","arm64","hetzner-ci"]
```

Se a variavel estiver vazia/ausente, os jobs continuam no runner hospedado da GitHub.

## Plano de execucao imediata (hoje)

1. Provisionar host Hetzner dedicado ao CI (x64 Linux).
2. Instalar runner com `scripts/ci/setup_github_runner_hetzner.sh`.
3. Definir variavel de repo `CI_RUNNER_LABELS` com labels do runner.
4. Abrir PR de smoke para validar execução no host Hetzner.
5. Monitorar 24h de estabilidade antes de escalar concorrencia.

## Passo a passo operacional

### 0) Bootstrap de root por chave (recomendado)

Para parar de depender de senha/sudo interativo no host, rode localmente:

```bash
./scripts/ci/bootstrap_hetzner_root_ssh.sh --host hetzner-cax21-helsinki-4vcpu-8gb-ipv4
```

Esse script:

- copia o `authorized_keys` do usuario remoto atual para `/root/.ssh/authorized_keys`
- define `PermitRootLogin prohibit-password`
- reinicia `ssh/sshd`

Depois disso, o teste esperado e:

```bash
ssh root@hetzner-cax21-helsinki-4vcpu-8gb-ipv4
```

### 1) Criar token de registro do runner

- GitHub repo -> Settings -> Actions -> Runners -> New self-hosted runner
- Copiar token temporario de registro

### 2) Instalar runner no Hetzner

No host Hetzner:

```bash
cd /path/do/repo
sudo bash scripts/ci/setup_github_runner_hetzner.sh \
  --url https://github.com/ToolHQ/production-site \
  --token <TOKEN_TEMPORARIO> \
  --name hetzner-ci-01 \
  --labels self-hosted,linux,arm64,hetzner-ci
```

### 2.1) Instalar varios runners na mesma maquina

Para paralelizar jobs na mesma instancia, use um runner por pasta/servico:

```bash
cd /path/do/repo
sudo bash scripts/ci/setup_github_runners_multi.sh \
  --url https://github.com/ToolHQ/production-site \
  --token <TOKEN_TEMPORARIO> \
  --count 3 \
  --name-prefix hetzner-ci- \
  --labels self-hosted,linux,arm64,hetzner-ci
```

Isso cria, por exemplo:

- `/opt/github-runners/hetzner-ci-01`
- `/opt/github-runners/hetzner-ci-02`
- `/opt/github-runners/hetzner-ci-03`

E os services:

- `github-runner-hetzner-ci-01.service`
- `github-runner-hetzner-ci-02.service`
- `github-runner-hetzner-ci-03.service`

### 3) Ligar workflows ao self-hosted

Criar/atualizar variavel `CI_RUNNER_LABELS` com:

```json
["self-hosted","linux","arm64","hetzner-ci"]
```

### 4) Smoke test

- Abrir PR pequena (ex: doc change)
- Confirmar jobs executando no runner `hetzner-ci-01`
- Validar tempo de fila, tempo total e estabilidade de rede

## Rollback rapido

Se o runner falhar:

1. Limpar variavel `CI_RUNNER_LABELS` (vazia) ou remover.
2. Re-run dos workflows -> jobs voltam para `ubuntu-latest`.

## Riscos e mitigacoes

- Runner indisponivel: manter fallback por variavel (ja implementado).
- Disco cheio no host: cron de limpeza para `_work` e caches.
- Codigo nao confiavel em PR publico: restringir permissao de runners para forks.
- Segredos: usar ambiente isolado e minimo privilegio.
- Colisao de portas/containers entre jobs paralelos: evitar bind fixo no host e preferir redes bridge/nomes unicos.

## Backlog recomendado (curto prazo)

1. Adicionar segundo runner (`hetzner-ci-02`) para redundancia.
2. Definir labels por classe de workload (`ci-light`, `ci-rust`).
3. Criar job de healthcheck diario do runner.
4. Alertar no Discord/Slack quando runner ficar offline.
