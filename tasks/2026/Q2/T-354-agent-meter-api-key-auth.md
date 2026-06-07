# T-354: agent-meter — Enforce API key authentication

- **Status**: To Do
- **Priority**: 🔼 High
- **Owner**: Copilot/VSCode
- **Estimate**: 3h

## Context

O sistema de API keys já está **100% funcional** para CRUD:
- `org_service.rs:L65-100`: `create_api_key()` gera `am_live_{uuid}_{uuid}`, hash SHA256, salva prefix
- `auth_service.rs:L274-296`: `lookup_api_key()` faz lookup por prefix + hash constant-time
- `routes/orgs.rs:L23-55`: `GET/POST/DELETE /api/orgs/:org_id/keys` — CRUD completo

**O que FALTA:** middleware Axum que intercept rotas `/api/*` e exige `Authorization: Bearer am_live_...`

**Config (`config.rs`):** Não tem campo `require_api_key`. Todas as rotas são abertas.
**Router (`app.rs:L23-42`):** 14 routers mergeados sem nenhum middleware de auth.

## Arquivos a modificar

| Arquivo | Ação |
|---------|------|
| `src/middleware/` | **CRIAR** diretório + `api_key_auth.rs` |
| `src/config.rs` | Adicionar `require_api_key: bool` (default false) |
| `src/app.rs` | Aplicar middleware nas rotas `/api/*` (L23-42) |
| `src/lib.rs` | Adicionar `pub mod middleware;` |

## Tasks

- [ ] Criar `src/middleware/mod.rs` + `api_key_auth.rs`
- [ ] Implementar middleware `ApiKeyAuth` como Axum `FromRequestParts`:
  - Extrair `Authorization: Bearer am_live_...` do header
  - Chamar `auth_service::lookup_api_key(pool, raw_key)` → retorna `org_id`
  - Inserir `org_id` no request extensions para uso downstream
  - Se inválido/revogado: retornar 401 com `{"error": "invalid api key"}`
- [ ] Adicionar `require_api_key: bool` em `config.rs` (env `REQUIRE_API_KEY`, default `false`)
- [ ] Em `app.rs`: quando `require_api_key=true`, aplicar middleware em rotas `/api/*`
  - Excluir: `/health`, `/v1/traces` (OTLP), `/api/billing/webhook` (Stripe)
- [ ] Propagar `org_id` do middleware para filtrar dados nos services (queries com `WHERE org_id = $N`)
- [ ] Testar: request sem key → 401, com key válida → 200 + dados filtrados por org
- [ ] Testar: key revogada → 401
