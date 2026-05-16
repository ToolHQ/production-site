# T-193: Master rootfs cleanup — BuildKit cache + legado MinIO

- **Status**: In Progress
- **Priority**: 🔼 High
- **Epic/Owner**: Infra / Ops
- **Estimation**: 2h
- **Opened**: 2026-05-16

## Context

O `oci-k8s-master` (49 GiB rootfs) acumulou pressão de disco que bloqueou builds Rust do AI Radar (`no space left on device` no BuildKit). Análise em 2026-05-16:

| Candidato | Tamanho | Natureza |
| --------- | ------- | -------- |
| `/data/minio_legacy_backup.tar` | ~11 GiB | Arquivo pós-cutover MinIO→Longhorn (**T-150**); operador confirmou que não precisa mais do rollback local |
| `~ubuntu/.local/share/buildkit` | ~4,5 GiB | Cache **rootless** órfão (serviço user `buildkit` failed; builds usam `sudo buildkitd` em `/var/lib/buildkit`) |
| `/tmp/build-swap` | ~2 GiB | Swap file legado (`swapon` ativo) |
| `/var/lib/buildkit` (root) | 5–17 GiB | Cache **transiente** — prune após builds, `keepstorage=10GB` no `buildkitd.toml` |
| apt/snap/crictl/logs | ~1–3 GiB | `clean_node.sh --deep` |

**Meta:** manter **≥ 12 GiB livres** no `/` entre builds (pré-voo AI Radar) e **≥ 18 GiB** só no pico de build Rust se o cache não foi podado.

## Tasks

- [x] Autorização do operador: remover `minio_legacy_backup.tar` (MinIO em Longhorn validado)
- [x] Remover `/data/minio_legacy_backup.tar` no master
- [x] Limpar cache rootless `~/.local/share/buildkit` (daemon inativo)
- [x] Desativar e remover `/tmp/build-swap`
- [x] Rodar `clean_node.sh --deep` no master (journal, apt, crictl, buildctl prune best-effort)
- [x] Após build API AI Radar: `buildctl prune --all` no socket root (~23 GiB reclaimable)
- [x] Ajustar pré-voo `deploy.sh`: `AI_RADAR_BUILD_MIN_FREE_GB` default **12** (pós-higiene)
- [x] Documentar candidatos e ganhos em `.agents/skills/deploy-service/SKILL.md`
- [ ] Validar `df -h /` e smoke deploy AI Radar sem `no space left on device`
- [ ] Opcional follow-up: CronJob/hook pós-build ou mover cache BuildKit para volume dedicado

## Execução (2026-05-16)

| Ação | Antes | Depois |
| ---- | ----- | ------ |
| `df /` | **92%** (~4,3 GiB livres) | **~58–59%** (~**21 GiB** livres) |
| `minio_legacy_backup.tar` | 11 GiB | removido |
| rootless buildkit | 4,5 GiB | ~4 KiB (dir vazio) |
| `/tmp/build-swap` | 2 GiB (ativo) | removido + `swapoff` |
| `clean_node --deep` | — | +76 MB (build ativo preservou cache root) |
| `buildctl prune --all` (pós-build API) | cache ~17 GiB | **~23 GiB** reclaimable; `/` **29%** usado (~**35 GiB** livres) |

## References

- **T-150** — cutover MinIO / `minio-legacy-cleanup-job.yaml`
- `oci-k8s-cluster/scripts/system_cleaner/clean_node.sh`
- `apps/ai-radar/deploy.sh` — `preflight_buildkit_disk`
- `.agents/skills/deploy-service/SKILL.md`

## Validação

```bash
ssh oci-k8s-master 'df -h /; sudo du -sh /var/lib/buildkit /data; ls -la /data/'
# Após deploy: buildctl prune + redeploy ai-radar com pré-voo OK
```
