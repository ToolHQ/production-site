# T-354: agent-meter — Enforce API key authentication

- **Status**: To Do
- **Priority**: 🔵 Medium
- **Owner**: Copilot/VSCode
- **Estimate**: 3h

## Context

`org_service.rs` menciona `REQUIRE_API_KEY=true` como flag para exigir API key em requests,
mas o middleware de autenticação não está implementado. Qualquer pessoa com acesso à URL
pode ler todas as conversas e custos.

O sistema de API keys já funciona (create, list, revoke, SHA256 hash), falta o middleware.

## Tasks

- [ ] Criar middleware Axum que extrai `Authorization: Bearer am_...` do header
- [ ] Lookup: hash SHA256 do token → tabela `api_keys` → obter `org_id`
- [ ] Atualizar `last_used_at` na key
- [ ] Aplicar middleware em todas as rotas `/api/*` (exceto `/health` e `/v1/traces`)
- [ ] Flag `REQUIRE_API_KEY` env var: quando false, permitir acesso sem key (dev mode)
- [ ] Filtrar dados por `org_id` quando autenticado por API key
- [ ] Testes: request sem key → 401, com key → 200 + dados filtrados
