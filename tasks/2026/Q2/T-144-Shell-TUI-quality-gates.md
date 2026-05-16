# T-144: Shell TUI quality gates

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: DevExp / Tooling
- **Estimation**: 4h

## Context
Com a T-142, o harness raiz já cobre `bash -n` e BATS. O próximo passo natural é endurecer a trilha de
shell com `shellcheck` e `shfmt`, mas sem transformar o repositório inteiro em bloqueante de uma vez.

O baseline real confirma que a superfície shell do repo está em dois estados diferentes:

- scripts gerenciados de tooling (`tools/**`, harness e runners curtos) estão perto de um baseline limpo e
	podem virar gate imediatamente
- superfícies maiores da TUI, como `oci-k8s-cluster/k8s_ops_menu.sh`, ainda acumulam débito histórico de
	`SC2155`, `SC2162`, `SC2181`, `SC1091` e similares; tentar forçar tudo de uma vez só abriria um refactor
	largo e arriscado fora do slice desta task

Hipótese local desta entrega: dá para introduzir `shellcheck` e `shfmt` como gates reais nas superfícies
shell gerenciadas, mantendo BATS e `bash -n` como cobertura segura do TUI amplo. Isso endurece o fluxo sem
bloquear a operação por dívida histórica ainda não ratchetada.

### Arquivos centrais

- [tools/harness/verify.sh](/home/ToolHQ/production-site/tools/harness/verify.sh)
- [tools/manage_tasks.sh](/home/ToolHQ/production-site/tools/manage_tasks.sh)
- [tools/helm_compat.sh](/home/ToolHQ/production-site/tools/helm_compat.sh)
- [oci-k8s-cluster/run_tests.sh](/home/ToolHQ/production-site/oci-k8s-cluster/run_tests.sh)
- [oci-k8s-cluster/testing/k8s_ops_menu.bats](/home/ToolHQ/production-site/oci-k8s-cluster/testing/k8s_ops_menu.bats)

## Tasks

- [x] Medir o baseline real de `shellcheck` antes de ligar o gate no harness
- [x] Definir um escopo seguro de superfícies shell gerenciadas para `shellcheck` e `shfmt`
- [x] Integrar `shellcheck` ao harness para os scripts gerenciados
- [x] Adicionar wrapper compatível para `shfmt` com bootstrap local quando a ferramenta não existir no host
- [x] Corrigir warnings de `shellcheck` nos scripts gerenciados tocados nesta task
- [x] Validar `verify-changed` e `verify-all` com os novos gates shell

## Entrega

- `tools/harness/verify.sh` agora aplica `shellcheck` e `shfmt` como gates reais em escopo shell gerenciado
- escopo de quality gate ficou explicitamente incremental: harness e tooling local (`tools/harness/**`, `tools/manage_tasks.sh`, `tools/shfmt_compat.sh`, `tools/helm_compat.sh`) e bootstrap de BATS (`oci-k8s-cluster/run_tests.sh`, `oci-k8s-cluster/testing/setup_bats.sh`)
- `tools/shfmt_compat.sh` adiciona resolução compatível do `shfmt` (binário do sistema quando suficiente, fallback para download/cache local)
- `tools/manage_tasks.sh` foi endurecido para baseline mais seguro (`set -euo pipefail`, validação de argumentos e ajustes shellcheck)
- `oci-k8s-cluster/testing/setup_bats.sh`, `oci-k8s-cluster/run_tests.sh` e `tools/helm_compat.sh` foram alinhados com `shfmt` para manter `verify-all` verde no escopo atual

## Validação

- `./tools/harness/verify.sh verify-changed --paths tools/harness/verify.sh tools/manage_tasks.sh tools/shfmt_compat.sh tasks/KANBAN.md tasks/2026/Q2/T-144-Shell-TUI-quality-gates.md`
- `./tools/harness/verify.sh verify-changed --paths tools/harness/verify.sh tools/harness/lib/changed_paths.sh tools/manage_tasks.sh tools/shfmt_compat.sh oci-k8s-cluster/testing/setup_bats.sh oci-k8s-cluster/run_tests.sh tasks/KANBAN.md tasks/2026/Q2/T-144-Shell-TUI-quality-gates.md`
- `./tools/harness/verify.sh verify-all`
- durante a validação, o gate apontou drifts reais de formatação em scripts do escopo gerenciado; os arquivos foram normalizados com `./tools/shfmt_compat.sh -w ...` e a reexecução final do `verify-all` passou com sucesso
