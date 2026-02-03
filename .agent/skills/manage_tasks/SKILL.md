# Skill: Manage Tasks
---
name: manage_tasks
description: Processo de gestão de tarefas e KANBAN do projeto.
---

Este skill descreve como o agente deve gerenciar o ciclo de vida das tarefas no repositório.

## Regras de Execução
1. **Sempre** verificar o `tasks/KANBAN.md` ao receber um novo pedido.
2. Usar o script `./tools/manage_tasks.sh` para qualquer alteração em tarefas.
3. **Fluxo de Trabalho**:
   - `add`: Para novas solicitações.
   - `start`: Quando começar a implementação técnica.
   - `done`: Ao finalizar e validar.

## Localização dos Arquivos
- **KANBAN**: `tasks/KANBAN.md`
- **Detalhes da Tarefa**: `tasks/T-XXX-Nome.md`
- **Ferramenta**: `tools/manage_tasks.sh`
