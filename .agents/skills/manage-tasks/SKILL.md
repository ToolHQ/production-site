---
name: manage-tasks
description: Processo de gestão de tarefas e KANBAN do projeto.
---

# Skill: Manage Tasks

Este skill descreve como o agente deve gerenciar o ciclo de vida das tarefas no repositório.

## Regras de Execução

1. **Sempre** verificar o `tasks/KANBAN.md` ao receber um novo pedido.
2. **Cursor**: operar em `~/production-site-cursor`; priorizar `tasks/CURSOR-QUEUE.md`; owner **AI Radar** = `Cursor / AI Radar` no KANBAN. Ver [docs/agent-orchestration.md](../../docs/agent-orchestration.md).
3. Usar o script `./tools/manage_tasks.sh` para qualquer alteração de estado (add/start/done).
4. **Detalhamento Obrigatório**: Ao criar ou iniciar uma tarefa, o agente DEVE editar o arquivo `tasks/T-XXX.md` para:
   - Expandir a seção `## Context` com detalhes técnicos do problema.
   - Quebrar a seção `## Tasks` em sub-tarefas granulares (ex: "Criar configmap", "Validar log", "Testar persistência").
5. **Atualização Contínua**: À medida que progride, o agente deve marcar os itens de `## Tasks` como concluídos (`[x]`). Não deixe a tarefa com apenas um item genérico.
6. **GitFlow Obrigatório**: Antes de executar qualquer alteração no código, crie uma nova branch a partir da `main` atualizada (ex: `feat/T-XXX-nome-da-feature`). **Nunca** commite diretamente na `main`. Todo o trabalho deve ser mesclado através de um Pull Request (PR).

## Fluxo de Trabalho

- `add`: Cria o esqueleto inicial.
- **Edição Manual (Obrigatória)**: Imediatamente após o `add`, use `replace_file_content` para popular o contexto e as sub-tarefas.
- `start`: Move para "In Progress".
- `done`: Move para "Done" após validar todos os pontos.

## Estrutura de uma Boa Tarefa

```markdown
# T-999: Nome da Tarefa

- **Status**: ...
- **Priority**: ...

## Context

Explicação técnica detalhada do PORQUÊ e COMO.

## Tasks

- [x] Sub-tarefa 1 concluída
- [/] Sub-tarefa 2 em progresso
- [ ] Sub-tarefa 3 pendente
```
