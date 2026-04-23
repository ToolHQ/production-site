# T-148: Harness Execution Summary

- **Status**: Done
- **Priority**: High
- **Epic/Owner**: DevExp / Tooling
- **Estimation**: 2h

## Context

Frente 6 do T-141 — Quality Harness Program. O `verify.sh` já roda múltiplos gates (shell,
rust, bats, js, yaml) mas não emite nenhum resumo ao final. O dev precisa scrollar o log para
saber quais gates passaram e quanto tempo cada um levou.

Solução: adicionar `timed_gate()` e `print_summary()` ao `tools/harness/verify.sh`. Ao final
de cada invocação `verify-changed` ou `verify-all`, imprimir tabela com: Gate | Result | Time.
Usar `trap 'print_summary' EXIT` para garantir que o sumário aparece mesmo em falha.

## Tasks

- [x] Criar e iniciar tarefa T-148
- [ ] Adicionar globals `HARNESS_RESULTS` e `HARNESS_START` ao verify.sh
- [ ] Implementar `timed_gate()` — captura rc e elapsed, registra em HARNESS_RESULTS
- [ ] Implementar `print_summary()` — tabela Gate|Result|Time + totais
- [ ] Adicionar `trap 'print_summary' EXIT` em `main()` para verify-changed/verify-all
- [ ] Converter chamadas de gate em `verify_changed` e `verify_all` para `timed_gate`
- [ ] Adicionar registros SKIP para gates não selecionados
- [ ] Validar output com `verify-all` e `verify-changed`
- [ ] Commit e fechar tarefa

## Tasks

# TODO: Quebre em tarefas menores e marque o progresso.

- [ ] Initial investigation
- [ ] Implement focus area 1
- [ ] Validate and test
