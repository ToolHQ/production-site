# T-311: Hetzner BuildKit disk growth guardrails

- **Status**: Backlog
- **Priority**: 🚨 Critical
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 1d

## Context

O host Hetzner `ubuntu-8gb-hel1-3` está com `/` em **90%** (`65G/75G`). Serviços estão saudáveis e os runners `hetzner-ci-01/02/03` estão ativos, mas `docker system df` reporta volume local de **39.2G** associado ao buildx/buildkit. Há build cache adicional de ~2G.

Como o Hetzner é builder CI/CD, o crescimento sem limite pode derrubar builds e deploys. Precisamos descobrir a causa exata e implementar guardrails de prune/retention conectados ao source (setup de builder, scripts de CI e TUI/infra ops).

## Tasks

- [ ] Inspecionar volume `buildx_buildkit_hetzner-builder0_state` e confirmar o que ocupa ~39.2G.
- [ ] Mapear quais workflows/deploys escrevem no builder e se usam `--load`, cache local ou registros temporários.
- [ ] Definir política de prune segura: idade, tamanho máximo e exceções para builds ativos.
- [ ] Implementar timer/script idempotente para `docker buildx prune`/BuildKit GC com dry-run/log.
- [ ] Integrar no setup do Hetzner builder e/ou TUI hardening para reaplicar em rebuild.
- [ ] Documentar capacidade, thresholds e comandos de emergência.
- [ ] Validar redução de disco sem quebrar `oci-builder`/fallback CI.

## Validação

```bash
ssh hetzner-cax21-helsinki-4vcpu-8gb-ipv4 "df -h /; docker system df; docker buildx ls"
```

Critério de aceite: disco abaixo de 75%, política automática versionada e builds ainda verdes.
