# T-142: Repo Root Harness Minimum Viable Verify

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: DevExp / Tooling
- **Estimation**: 4h

## Context
O programa definido na [T-141](/home/dnorio/production-site/tasks/2026/Q2/T-141-Repo-Quality-Harness-and-Delivery-Gates-Program.md)
precisa começar pelo menor slice que já entregue valor real sem virar framework interno pesado. O repositório
não possui `Makefile`, root runner ou workflow único de validação. Na prática, os checks continuam
espalhados por stack e dependem de memória tácita do operador.

O melhor ponto de partida local é um harness shell-based em `tools/harness/` porque:

- o repo já usa shell como cola operacional principal
- não existe runtime raiz único para centralizar isso via Node ou Cargo workspace
- o primeiro valor útil cabe em dispatch por caminho alterado, sem tentar cobrir o monorepo inteiro agora

Nesta task, o escopo seguro é entregar o runner mínimo com três entradas públicas:

- `verify-changed`: seleciona gates a partir do diff local ou de paths explícitos
- `verify-all`: roda a baseline atualmente suportada
- `smoke`: placeholder explícito, para reservar a interface sem prometer comportamento antes da T-143/T-144

Cobertura inicial desta fatia:

- `apps/rs-observability-api/**` -> `cargo fmt --check`, `cargo clippy`, `cargo test`
- `oci-k8s-cluster/**` tocando shell/test surface -> `run_tests.sh`
- shell scripts tocados em `tools/**`, `apps/*/deploy.sh` e `oci-k8s-cluster/**` -> `bash -n`

Decisão de segurança desta fase:

- paths ainda não mapeados devem ser reportados como `unmapped`; por padrão, `verify-changed` falha nesse
	caso para evitar falsa sensação de cobertura
- é permitido um escape hatch explícito (`--allow-unmapped`) para uso transitório durante o rollout

### Arquivos centrais

- [tools/manage_tasks.sh](/home/dnorio/production-site/tools/manage_tasks.sh)
- [apps/rs-observability-api/Cargo.toml](/home/dnorio/production-site/apps/rs-observability-api/Cargo.toml)
- [oci-k8s-cluster/run_tests.sh](/home/dnorio/production-site/oci-k8s-cluster/run_tests.sh)
- [tasks/KANBAN.md](/home/dnorio/production-site/tasks/KANBAN.md)

## Tasks

- [x] Confirmar a ausência de um harness raiz e escolher shell como camada de orquestração mínima
- [x] Corrigir a duplicação acidental `T-142`/`T-143` gerada durante o bootstrap da task
- [x] Criar a estrutura `tools/harness/` com dispatcher e detector de changed paths
- [x] Implementar `verify-changed` com gates iniciais para Rust, shell syntax e BATS do cluster tooling
- [x] Implementar `verify-all` com a baseline hoje suportada
- [x] Expor `smoke` como comando reservado e explicitamente não implementado nesta task
- [x] Validar o harness com execução real nos paths tocados nesta entrega

## Entrega

- harness raiz mínimo adicionado em `tools/harness/`
- contrato inicial disponível via `./tools/harness/verify.sh verify-changed` e
	`./tools/harness/verify.sh verify-all`
- cobertura inicial focada em `rs-observability-api`, shell syntax e suíte BATS do `oci-k8s-cluster`
- comportamento seguro para áreas ainda não cobertas: `unmapped` falha por padrão em `verify-changed`
- `./tools/harness/verify.sh` marcado como executável para uso direto a partir da raiz do repo

## Validação

- `bash ./tools/harness/verify.sh verify-changed --paths tools/harness/verify.sh tools/harness/lib/changed_paths.sh tasks/KANBAN.md tasks/2026/Q2/T-142-Repo-Root-Harness-Minimum-Viable-Verify.md apps/rs-observability-api/src/main.rs`
- durante a primeira execução, o gate falhou corretamente em `cargo fmt --check` por drift real já existente em `apps/rs-observability-api/src/main.rs`; o baseline foi corrigido com `cargo fmt`
- reexecução do mesmo comando: `shell syntax` passou para os scripts do harness e o gate Rust passou em `fmt`, `clippy` e `test`
- `./tools/harness/verify.sh verify-changed --paths oci-k8s-cluster/testing/k8s_ops_menu.bats`
- a chamada direta executou `oci-k8s-cluster/run_tests.sh` com `15 tests, 0 failures`
- `./tools/harness/verify.sh verify-all`
- a baseline completa passou com `bash -n` nos scripts suportados, `cargo fmt --check`, `cargo clippy`, `cargo test` em `apps/rs-observability-api` e novamente `15 tests, 0 failures` na suíte BATS
