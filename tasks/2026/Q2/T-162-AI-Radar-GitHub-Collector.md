# T-162: AI Radar — GitHub Collector

- **Status**: Done
- **Priority**: 🔽 Low
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 1d
- **Opened**: 2026-05-01

## Context

Collector para GitHub REST API: monitora releases novas e metadados de repos (stars, forks, license, pushed_at) de fontes do tipo `github_repo` e `github_releases`. `external_id = release.id` permite dedup forte (sem precisar de hash).

Token opcional via `GITHUB_TOKEN` (sem token = 60 req/h, com token = 5000 req/h). Respeitar headers `x-ratelimit-*` e esperar até `reset` quando necessário (cap 90s para não travar pipeline).

## Tasks

- [x] Struct `GitHubClient` em `ai-radar-core::collector::github::client` com headers padrão (User-Agent, Accept, Authorization opcional)
- [x] Métodos: `get_repo(owner, repo)`, `list_releases(owner, repo, since)`, `get_readme(owner, repo)`
- [x] Tratamento de rate-limit: `x-ratelimit-remaining` + `x-ratelimit-reset` → retornar `Err(RateLimited)` ou esperar curto (cap 90s)
- [x] `GitHubReleasesCollector` mapeando `release.id` → `external_id`, `body` → `raw_content`
- [x] `GitHubRepoMetaCollector` persistindo metadados como JSON em `raw_items.raw_content`
- [x] Paginação por header `Link` (cap 3 páginas = 90 items por execução)
- [x] Wrapper `with_rate_limit_retry` para chamadas GitHub _(via `with_retry` + rate-limit wait)_
- [x] Integração com pipeline collect: source_type `github_releases`/`github_repo` despacha pro client adequado
- [x] Mock HTTP com `wiremock-rs` cobrindo: 200, 401, 403 rate-limited, 500, paginação
- [x] Documentar no README: limites com/sem token

## DoD

- Adicionar source `github_releases` com URL `https://github.com/owner/repo` → coleta releases.
- 2ª execução não duplica (`external_id` UNIQUE).
- Funciona sem `GITHUB_TOKEN` (limite menor) e com token (sem warns).
- Rate-limit forte → cliente espera/loga corretamente, não trava.
- Mocks cobrem 5+ cenários.

## Validação

```bash
cd apps/ai-radar
export GITHUB_TOKEN=ghp_...   # opcional
curl -X POST localhost:8080/sources -H 'Content-Type: application/json' \
  -d '{"name":"Rust releases","source_type":"github_releases","url":"https://github.com/rust-lang/rust"}'

cargo run -p ai-radar-cli -- collect --source-type github_releases
psql $DATABASE_URL -c "SELECT external_id, title FROM ai_radar.raw_items WHERE source_id IN (SELECT id FROM ai_radar.sources WHERE source_type='github_releases') LIMIT 5"
cargo test -p ai-radar-core --test github_collector
```

## References

- `docs/AI-RADAR-DECISIONS.md`
- `docs/AI-RADAR-ROADMAP.md` — Fase 4
- Depende de: **T-160** (paralelizável com T-161)
- Branch sugerida: `feat/T-162-ai-radar-github-collector`
