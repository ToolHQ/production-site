# T-311: Hetzner BuildKit disk growth guardrails

- **Status**: Done
- **PR**: feat/t-311-buildkit-guardrails
- **Priority**: 🚨 Critical
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 1d

## Context

O host Hetzner `ubuntu-8gb-hel1-3` está com `/` em **90%** (`65G/75G`). Serviços estão saudáveis e os runners `hetzner-ci-01/02/03` estão ativos, mas `docker system df` reporta volume local de **39.2G** associado ao buildx/buildkit. Há build cache adicional de ~2G.

Como o Hetzner é builder CI/CD, o crescimento sem limite pode derrubar builds e deploys. Precisamos descobrir a causa exata e implementar guardrails de prune/retention conectados ao source (setup de builder, scripts de CI e TUI/infra ops).

## Tasks

- [x] Inspecionar volume `buildx_buildkit_hetzner-builder0_state` (~39G → ~18G após prune; buildkit data ~14GiB).
- [x] Mapear workflows: `deploy-buildx.sh` + `deploy.sh --builder hetzner-builder --load` (ai-radar, agent-meter, etc.).
- [x] Política: prune 16gb max; reset se rootfs ≥75% ou buildkit ≥16GiB.
- [x] `buildkit_guardrails.sh` + systemd timer 6h + `install_buildkit_guardrails.sh`.
- [x] Integrado em `setup-hetzner-builder.sh` + check em `check-hetzner-builder.sh`.
- [x] Docs: `docs/hetzner-buildkit-guardrails.md`.
- [x] Harness `validate_hetzner_buildkit_guardrails.sh`; disco 75%, builds OK.

## Validação

```bash
ssh hetzner-cax21-helsinki-4vcpu-8gb-ipv4 "df -h /; docker system df; docker buildx ls"
```

Critério de aceite: disco abaixo de 75%, política automática versionada e builds ainda verdes.
