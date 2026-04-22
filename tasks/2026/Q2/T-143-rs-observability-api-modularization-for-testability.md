# T-143: rs-observability-api modularization for testability

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: DevExp / Observability
- **Estimation**: 6h

## Context
O `rs-observability-api` cresceu rápido e hoje concentra montagem do router, handlers HTTP, leitura de
artefatos de relatório e lógica de summary diretamente em [apps/rs-observability-api/src/main.rs](/home/dnorio/production-site/apps/rs-observability-api/src/main.rs).
Isso dificulta testes direcionados porque qualquer validação acaba encostando no arquivo monolítico e na
função `main`, mesmo quando o comportamento a verificar é puramente HTTP/reporting.

O seam local mais barato e útil é extrair o bloco de HTTP/reporting para um módulo filho, preservando o
runtime existente de monitores live/Prometheus, mas criando uma superfície testável para:

- montagem do router
- endpoint `/health`
- endpoint `/api/catalog/summary`
- regras de segurança de path para artefatos

Hipótese desta task: se o router e os handlers de relatório saírem de `main.rs` para um módulo dedicado,
fica possível testar contrato HTTP em memória com `cargo test`, sem alterar o comportamento runtime do app.

### Arquivos centrais

- [apps/rs-observability-api/src/main.rs](/home/dnorio/production-site/apps/rs-observability-api/src/main.rs)
- [apps/rs-observability-api/Cargo.toml](/home/dnorio/production-site/apps/rs-observability-api/Cargo.toml)
- [tools/harness/verify.sh](/home/dnorio/production-site/tools/harness/verify.sh)

## Tasks

- [x] Confirmar o melhor seam local para testabilidade sem reescrever o app inteiro
- [x] Extrair a montagem do router e o bloco HTTP/reporting para um módulo dedicado
- [x] Introduzir uma função pura para montagem do `CatalogSummary`
- [x] Adicionar testes de rota em memória para `/health` e `/api/catalog/summary`
- [x] Adicionar teste de segurança para `resolve_relative_path`
- [x] Validar a nova estrutura com `cargo test`, `cargo clippy` e o harness raiz

## Entrega

- `apps/rs-observability-api/src/app.rs` passou a concentrar a montagem do router e os handlers de HTTP/reporting
- `apps/rs-observability-api/src/main.rs` ficou focado em bootstrap, estado e coletores live/Prometheus
- a lógica de resumo do catálogo foi extraída para uma função pura (`catalog_summary_from_catalog`), reduzindo o acoplamento do handler
- testes de rota em memória agora cobrem o contrato de `/health` e `/api/catalog/summary`
- um teste de segurança cobre `resolve_relative_path`, garantindo rejeição de path absoluto e traversal
- `Cargo.toml` recebeu `tower` em `dev-dependencies` para suportar `oneshot` nos testes do router

## Validação

- `cd apps/rs-observability-api && cargo test`
- `cd apps/rs-observability-api && cargo clippy --all-targets --all-features -- -D warnings`
- `./tools/harness/verify.sh verify-changed --paths apps/rs-observability-api/Cargo.toml apps/rs-observability-api/src/main.rs apps/rs-observability-api/src/app.rs tasks/KANBAN.md tasks/2026/Q2/T-143-rs-observability-api-modularization-for-testability.md`
- a primeira execução do harness falhou corretamente em `cargo fmt --check` por drift local no novo `app.rs`; o baseline foi alinhado com `cargo fmt`
- a reexecução do mesmo `verify-changed` passou em `fmt`, `clippy` e `test`, com `3 passed; 0 failed`
