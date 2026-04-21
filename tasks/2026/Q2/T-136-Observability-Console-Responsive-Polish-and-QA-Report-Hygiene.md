# T-136: Observability Console Responsive Polish and QA Report Hygiene

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: DevExp / Observability
- **Estimation**: 4h

## Context
O baseline operations-first de T-135 ficou funcional e já está no ar, mas ainda há dois débitos claros
antes de considerar a tela madura:

- artefatos gerados de QA continuam espalhados entre a raiz do repositório e `tmp/ui-audit`
- a responsividade ainda não está no nível esperado em mobile e em monitores largos

No mobile, a primeira dobra ainda consome altura demais com empilhamento generoso, pills longos e cards
de status ocupando mais espaço vertical do que o necessário para triagem.

Em telas largas, alguns grids ainda desperdiçam área útil, especialmente quando painéis com pouco conteúdo
esticam para acompanhar colunas vizinhas mais altas, o que reduz a sensação de dashboard denso.

O objetivo desta tarefa é:

- mover relatórios gerados para uma quarentena local em `.qa/reports`
- tirar esses artefatos do diff normal via `.gitignore`
- registrar um commit limpo do baseline já entregue
- aplicar uma segunda passada de polish em `apps/rs-observability-api/web/index.html`
	focada em densidade mobile e melhor uso de largura em desktop grande

### Restrições

- manter o frontend estático, sem dependências novas
- preservar o payload atual do backend
- seguir a filosofia `Stability First`
- manter o deploy compatível com o fluxo OCI/Nexus atual

### Arquivos centrais

- `apps/rs-observability-api/web/index.html`
- `.gitignore`
- `tasks/KANBAN.md`
- `tasks/2026/Q2/T-135-Observability-Console-Operations-First-UX-Refactor.md`

## Tasks
- [x] Mover relatórios gerados de Lighthouse e screenshots para `.qa/reports`
- [x] Adicionar `.qa/reports/` ao `.gitignore`
- [x] Organizar o diff atual e registrar um commit de baseline/housekeeping
- [x] Reduzir altura e ruído da primeira dobra no mobile
- [x] Compactar mini-métricas e pills de metadata em breakpoints pequenos
- [x] Melhorar colunagem e densidade para monitores largos
- [x] Corrigir stretch excessivo em painéis com pouco conteúdo
- [x] Gerar screenshots mobile, desktop e wide após o polish
- [x] Validar frontend e deploy após a segunda passada
- [x] Atualizar tarefa/KANBAN e registrar commit final do polish

## Resultado

- os relatórios gerados de Lighthouse e screenshots passaram a ficar em `.qa/reports`, saindo da raiz do repositório e do fluxo normal de diff
- a home em `apps/rs-observability-api/web/index.html` ganhou uma segunda passada específica de responsividade
- no mobile, a primeira dobra foi compactada com pills menos pesados, cards mais densos e menor consumo vertical na abertura
- em desktop largo, o grid principal passou a usar melhor a largura disponível com distribuição mais eficiente entre hero, watch card, serviços e superfície secundária
- os painéis de prioridade deixaram de esticar desnecessariamente para acompanhar a altura do vizinho, reduzindo sensação de vazio

## Validação

- `get_errors` no HTML retornou sem erros após as alterações
- deploy validado com rollout estável de `rs-observability-api-deployment`
- `https://reports.dnor.io/` respondeu `HTTP 200`
- `https://reports.dnor.io/api/live/overview` continuou coerente com `available: true`, `6/6` serviços críticos saudáveis e `4/4` nodes prontos
- screenshots finais capturados em:
	- `.qa/reports/ui-audit/mobile-polish.png`
	- `.qa/reports/ui-audit/desktop-polish.png`
	- `.qa/reports/ui-audit/wide-polish.png`
