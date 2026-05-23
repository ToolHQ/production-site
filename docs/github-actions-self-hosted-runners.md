# GitHub Actions — Migracao para Self-Hosted (Hetzner)

## Objetivo

Reduzir custo de GitHub Actions movendo execucao de CI para runner self-hosted no Hetzner.

## O que ja foi preparado no repo

- Workflows usam `CI_RUNNER_LABELS` com fallback seguro para `ubuntu-latest`:
  - `.github/workflows/quality-gates.yml`
  - `.github/workflows/auto-docs.yml`

Formato esperado de `CI_RUNNER_LABELS` em **Settings > Secrets and variables > Actions > Variables**:

```json
["self-hosted","linux","x64","hetzner-ci"]
```

Se a variavel estiver vazia/ausente, os jobs continuam no runner hospedado da GitHub.

## Plano de execucao imediata (hoje)

1. Provisionar host Hetzner dedicado ao CI (x64 Linux).
2. Instalar runner com `scripts/ci/setup_github_runner_hetzner.sh`.
3. Definir variavel de repo `CI_RUNNER_LABELS` com labels do runner.
4. Abrir PR de smoke para validar execução no host Hetzner.
5. Monitorar 24h de estabilidade antes de escalar concorrencia.

## Passo a passo operacional

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
  --labels self-hosted,linux,x64,hetzner-ci
```

### 3) Ligar workflows ao self-hosted

Criar/atualizar variavel `CI_RUNNER_LABELS` com:

```json
["self-hosted","linux","x64","hetzner-ci"]
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

## Backlog recomendado (curto prazo)

1. Adicionar segundo runner (`hetzner-ci-02`) para redundancia.
2. Definir labels por classe de workload (`ci-light`, `ci-rust`).
3. Criar job de healthcheck diario do runner.
4. Alertar no Discord/Slack quando runner ficar offline.
