# T-200: AI Radar — otimização de tempo de compilação (Rust / BuildKit)

- **Status**: Backlog
- **Priority**: 🔼 High
- **Owner**: **Cursor / AI Radar**
- **Epic**: AI Radar / DevExp
- **Est.**: 1d

## Context

Deploys do AI Radar no `oci-k8s-master` (buildx ARM64 remoto) levam **~45–55 min** típicos porque:

1. **`deploy.sh` compila API + CLI em sequência** — dois pipelines BuildKit completos por rollout.
2. **Workspace Rust pesado** — `sqlx`, `reqwest`/rustls, `aws-lc-sys` (via cadeia TLS), rebuild de deps quando o layer de stub invalida cache.
3. **Dockerfile atual** — stub `cargo build` + `touch` + rebuild funciona, mas não usa **`cargo-chef`** (mencionado em `docs/AI-RADAR-DECISIONS.md`).
4. **T-193 / T-196** tratam **disco e prune do BuildKit**, não tempo de compilação em si.

Ganho esperado: cada PR/deploy AI Radar **10–25 min mais rápido** após cache quente; impacto multiplicador em todas as tasks Cursor/Copilot que tocam `apps/ai-radar/`.

## Tasks

- [ ] Medir baseline: `time deploy.sh` (api only vs api+cli), tamanho cache `/var/lib/buildkit`, layers reutilizados
- [ ] Introduzir **`cargo-chef`** em `docker/Dockerfile.api` e `docker/Dockerfile.cli` (recipe + cook; compartilhar `chef prepare` entre imagens)
- [ ] Flag `AI_RADAR_DEPLOY_CLI=0` (ou detectar diff só em api) para pular build CLI quando CronJob image inalterada
- [ ] Avaliar **`sccache`** no builder remoto (bucket MinIO/NFS free-tier) vs só BuildKit layer cache
- [ ] Revisar `CARGO_INCREMENTAL=0` + `lto` no workspace — manter binário pequeno, cortar LTO se ativo
- [ ] Documentar no README o “fast path” e requisitos de cache (alinhado T-196)
- [ ] Validar: segundo deploy seguido sem mudança de deps **&lt; 15 min**; smoke imagem ARM64 no cluster

## Referências

- `apps/ai-radar/docker/Dockerfile.api`, `Dockerfile.cli`, `deploy.sh`
- `docs/AI-RADAR-DECISIONS.md` — linha cargo-chef / matrix paralelo
- T-193, T-196 (disco BuildKit)

## Definition of Done

- Deploy repetido (sem mudança de `Cargo.lock`) comprovadamente mais rápido que o baseline documentado
- README/runbook com flags e expectativa de tempo
- CI/harness verde
