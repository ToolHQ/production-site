# T-315: agent-meter — Session Replay UI

## Objetivo
Criar uma interface de replay de interações que permita visualizar passo-a-passo como um "vídeo" de tool calls, com destaque para erros e padrões.

## Contexto
Enquanto a timeline mostra a sequência de events, o replay deve focar na experiência narrativa da interação, como se estivesse "replayer" uma sessão de desenvolvimento.

## Especificações

### 1. Modo de Replay
- **Controles**: play/pause, next/previous, speed (1x/2x/5x)
- **Destaque visual**:
  - Tool calls com `ok: false` em vermelho
  - Tool calls com payload grande (>100KB) em amarelo
  - Padrões repetidos (ex: múltiplos `read_file` seguidos)

### 2. Painel Lateral
- **Call Stack**: tools aninhadas (se houver)
- **Variables**: valores relevantes de cada call
- **Notes**: área para anotações manuais (salvas localmente)

### 3. Padrões Detectados
- **Sequential Reads**: múltiplos `read_file` sem interação humana
- **Retry Pattern**: falhas seguidas de sucesso
- **Token Spike**: tool que consumiu muito tokens de forma inesperada

### 4. Exportação
- **Session Summary**: JSON com resumo da sessão
- **Notes Export**: baixar anotações como Markdown

## Implementação

### Frontend
1. Criar componente `<SessionReplay />`
2. Store de replay state (redux/zustand)
3. Virtualização de events para performance
4. Anotações locais via `localStorage`

### Backend
1. Endpoint `GET /api/conversations/:id/patterns` para detectar padrões
2. Query SQL para identificar sequências

## Critérios de Aceitação
- [ ] Botão "Replay" aparece nas conversas
- [ ] Controles de replay funcionam
- [ ] Padrões são detectados e exibidos
- [ ] Anotações salvas localmente
- [ ] Exportação de session summary funcional

## Estimativas
- Frontend: 3h
- Backend (padrões): 1h
- **Total**: ~4h

## Owner
**Copilot/VSCode**

## Status
- [ ] Frontend: Página `/conversations/:id` (aguardando implementação)
- [ ] Backend: Endpoint de padrões (não implementado)
- [ ] Anotações locais via localStorage

## Notas
- Pode reutilizar dashboard.html como base
- Componente TimelineView já parcialmente implementado no dashboard