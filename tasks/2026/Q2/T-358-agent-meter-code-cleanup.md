# T-358: agent-meter — Code quality: dead code removal + clippy

- **Status**: To Do
- **Priority**: 🔵 Medium
- **Owner**: Copilot/VSCode
- **Estimate**: 2h

## Context

O codebase acumulou debt técnico ao longo dos sprints rápidos.

**Dead code encontrado:**
- `proxy/src/interceptor.rs:L50`: `#[allow(dead_code)]` no campo `path: String`
- `collector/src/services/stripe_service.rs:L219`: `#[allow(dead_code)]` em field interno
- `billing.rs:L26-32`: `stub_page()` — placeholder HTML inline que deveria ser removido (T-356)

**Duplicação:**
- `otlp/mod.rs`: `extract_clean_user_prompt_json()` e `extract_clean_user_prompt_proto()` fazem a mesma lógica
- `proxy/src/interceptor.rs` vs `collector/src/otlp/mod.rs`: ambos parsam JSON de requests LLM

**Arquitetura:**
- `routes/mod.rs`: 15 módulos sem agrupamento
- `services/mod.rs`: 10 módulos flat
- `app.rs:L23-42`: 14 `.merge()` calls sem organização por domínio

**Eclipse proxy** (`eclipse-proxy/copilot_interceptor.py`): versão Python legada do proxy.

## Arquivos a verificar/limpar

| Arquivo | Problema |
|---------|----------|
| `proxy/src/interceptor.rs` | `#[allow(dead_code)]` em `path` field |
| `collector/src/services/stripe_service.rs` | `#[allow(dead_code)]` |
| `collector/src/otlp/mod.rs` | Duplicação json vs proto extraction |
| `eclipse-proxy/` | Verificar se está sincronizado ou se é dead code |
| Todos os `.rs` | `cargo clippy` warnings |

## Tasks

- [ ] `cd apps/agent-meter && cargo clippy --workspace -- -D warnings` — listar todos os warnings
- [ ] Corrigir cada warning do clippy (unused imports, redundant clones, etc.)
- [ ] Remover `#[allow(dead_code)]` em `interceptor.rs:L50` — usar o campo ou remover
- [ ] Remover `#[allow(dead_code)]` em `stripe_service.rs:L219`
- [ ] Consolidar `extract_clean_user_prompt_json()` e `_proto()` em uma única função genérica
- [ ] Verificar `eclipse-proxy/copilot_interceptor.py` — se proxy Rust é definitivo, mover para `archive/`
- [ ] Verificar `login.html` "More options coming soon" — remover texto se não planejado
- [ ] `cargo test --workspace` — garantir 0 falhas
- [ ] `cargo fmt --check` — garantir formatação consistente
