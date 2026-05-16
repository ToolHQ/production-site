# T-200 — Node Fleet Panel: Layout Polish

**Status**: Backlog  
**Owner**: Copilot/VSCode  
**Priority**: 🔽 Medium  
**Epic**: Cluster Pulse / Observability  
**Est.**: 1h

---

## Problema

O painel Node Fleet (T-199) ficou funcional mas visualmente estranho:

1. **Cabeçalhos redundantes** — "CPU (alloc.)" e "Memory (alloc.)" repetem o que o subtítulo do painel já diz ("Allocatable resources"). O usuário lê duas vezes a mesma informação.
2. **Coluna Ephemeral ambígua** — `43.4 GiB` é o ephemeral storage allocatable (fixo), não o uso de disco do nó. Parece dado de monitoramento mas é apenas capacidade reservada.
3. **Todos os valores são idênticos** — 800m / 5.2 GiB / 43.4 GiB para os 4 nós. A tabela não traz sinal nenhum de diferença entre nós, parece congelada/estática.
4. **Larguras de coluna desbalanceadas** — Node e Role competem com as colunas de métricas em espaço. Em telas médias o layout comprime mal.
5. **Sem unidade visual de "o que isso significa"** — falta contexto de "isto é alocável, não em uso".

---

## Escopo

Mudanças apenas em `NodesPanel.tsx` e CSS relacionado — **sem alterar a API Rust** (isso é T-201).

### Ações

- [ ] Renomear cabeçalhos para **`CPU`**, **`Memory`**, **`Disk`** (remover sufixo "(alloc.)")
- [ ] Adicionar tooltip ou label secundário discreto "(allocatable)" em cada header, não como texto principal
- [ ] Adicionar badge/pill `ALLOCATABLE` no header da tabela (canto superior direito) para indicar que toda a tabela é alocável — deixar claro de forma não-redundante
- [ ] Ajustar `col-width` das colunas: Node (24%), Role (16%), CPU (14%), Memory (14%), Disk (16%), Alerts (16%)
- [ ] Garantir que a linha highlight de `disk_pressure` / `not-ready` tenha contraste adequado em modo dark

---

## Contexto técnico

**Arquivo**: `apps/rs-observability-api/web-v2/src/components/NodesPanel.tsx`

Dado atual (imutável até T-201):
- `cpu_millicores` = `status.allocatable.cpu` do K8s (sempre `800m` por nó)
- `memory_bytes` = `status.allocatable.memory` do K8s (sempre `5.2 GiB`)
- `ephemeral_storage_bytes` = `status.allocatable.ephemeral-storage` do K8s (sempre `43.4 GiB`)

---

## Definition of Done

- [ ] Tabela legível sem "(alloc.)" repetido em cada coluna
- [ ] Layout não quebra em `1280px` de largura
- [ ] Coluna Alerts visível sem scroll horizontal
- [ ] Deploy em `reports.dnor.io` via PR
