# T-358: agent-meter — Code quality: remove dead code and TODO cleanup

- **Status**: To Do
- **Priority**: 🔵 Medium
- **Owner**: Copilot/VSCode
- **Estimate**: 2h

## Context

O codebase acumulou debt técnico ao longo dos sprints rápidos.
Precisa de uma passada de limpeza geral.

## Tasks

- [ ] `cargo clippy` em todos os crates — corrigir todos os warnings
- [ ] Remover funções não utilizadas (especialmente em `otlp/mod.rs`)
- [ ] Consolidar duplicação entre `extract_clean_user_prompt_json` e `extract_clean_user_prompt_proto`
- [ ] Remover `#[allow(dead_code)]` desnecessários
- [ ] Verificar `login.html` "More options coming soon" — remover se não planejado
- [ ] Limpar imports não usados em todos os arquivos
- [ ] Rodar `cargo test` e garantir 100% pass
- [ ] Verificar se `eclipse-proxy/copilot_interceptor.py` está sincronizado com o proxy Rust
