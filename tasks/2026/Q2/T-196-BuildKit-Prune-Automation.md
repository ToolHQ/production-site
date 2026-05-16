# T-196: BuildKit Prune Automation — hook pós-build + CronJob

- **Status**: Backlog
- **Priority**: 🔼 High
- **Epic/Owner**: Infra / Ops / **Copilot/VSCode**
- **Estimation**: 2h
- **Opened**: 2026-05-16

## Context

O `k8s-master` voltou a entrar em `DiskPressure` em 2026-05-16 (~15:07 UTC), apesar da limpeza realizada em T-193 (que liberou 35 GiB).
O cache do BuildKit (`/var/lib/buildkit`) cresce com cada build do AI Radar (CronJobs a cada 30 min) e não é purgado automaticamente.

T-149 ("DiskPressure Recurrence Hardening") foi marcada como Done, mas a recorrência prova que o mecanismo de prune não é suficientemente robusto.

**Meta:** garantir que `/var/lib/buildkit` nunca ultrapasse 10 GiB no master, sem intervenção manual.

## Abordagem proposta

### Opção A — Hook no `deploy.sh` (Recomendado)
Adicionar `preflight_buildkit_disk` no `apps/ai-radar/deploy.sh` para executar `buildctl prune --keep-storage=8589934592` (8 GiB) antes de cada build, além do check de espaço mínimo já existente.

### Opção B — CronJob Kubernetes
CronJob `buildkit-cache-pruner` rodando via `ssh oci-k8s-master` a cada 6h, pruning cache se > 10 GiB.
Mais robusto, mas depende de SSH key disponível no cluster (secret).

## Tasks

- [ ] Medir frequência de crescimento do cache: `ssh oci-k8s-master 'sudo du -sh /var/lib/buildkit'`
- [ ] Implementar opção A: prune pré-build no `deploy.sh` (keep-storage=8 GiB)
- [ ] Testar: rodar build AI Radar e verificar que cache não excede threshold
- [ ] Validar `df -h /` antes e depois: deve manter > 15 GiB livres
- [ ] Decidir se Opção B (CronJob) é necessária como camada adicional
- [ ] Atualizar `.agents/skills/deploy-service/SKILL.md` com o novo comportamento

## References

- **T-193** — higiene disco master (raiz do problema)
- **T-149** — DiskPressure Recurrence Hardening (primeira tentativa)
- `apps/ai-radar/deploy.sh` — `preflight_buildkit_disk`
- `oci-k8s-cluster/scripts/system_cleaner/clean_node.sh`

## Validação

```bash
# Verificar cache antes do build
ssh oci-k8s-master 'sudo du -sh /var/lib/buildkit'

# Rodar deploy e confirmar prune automático nos logs
cd apps/ai-radar && ./deploy.sh

# Verificar disco após build
ssh oci-k8s-master 'df -h /'
# Esperado: < 70% usado, > 15 GiB livres
```
