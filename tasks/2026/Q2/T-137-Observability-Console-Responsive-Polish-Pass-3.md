# T-137: Observability Console Responsive Polish Pass 3

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: DevExp / Observability
- **Estimation**: 3h

## Context
Após T-135 e T-136, a home já deixou de ser uma landing editorial e virou um console operacional
coerente. Mesmo assim, o uso real em browser mostrou dois gaps restantes:

- no mobile, a primeira dobra ainda está pesada demais, especialmente pelo peso do hero e pelo texto
	de metadata no topo
- em monitores grandes, a tela melhorou, mas ainda não aproveita a largura com a agressividade que um
	dashboard operacional pede

O screenshot atual confirma que o problema não é mais falta de informação nem semântica errada. O que
resta é densidade, ritmo visual e melhor priorização do bloco de watch/watchpoints em breakpoints extremos.

### Objetivo desta tarefa

Executar uma terceira passada de polish com foco explícito em:

- tornar o mobile mais operacional e menos editorial
- encurtar metadados e reduzir altura da primeira dobra em telas pequenas
- usar monitores largos com mais confiança, ampliando largura útil e densidade dos grids principais

### Restrições

- manter o frontend estático
- não alterar contrato do backend
- manter deploy compatível com o fluxo OCI/Nexus atual
- preservar o caráter operations-first conquistado em T-135/T-136

### Arquivo central

- `apps/rs-observability-api/web/index.html`

## Tasks
- [x] Reavaliar o topo da home em mobile e ultra-wide com base nas capturas atuais
- [x] Compactar hero, metadata pills e command card em telas pequenas
- [x] Melhorar densidade de métricas/cards em breakpoints intermediários
- [x] Expandir melhor o uso de largura em monitores largos
- [x] Validar visual com novas screenshots mobile, desktop e wide
- [x] Publicar no cluster e registrar o resultado na tarefa

## Entrega

- a home em `apps/rs-observability-api/web/index.html` ganhou uma terceira passada focada em densidade
	operacional por breakpoint, sem alterar o contrato do backend
- em mobile, o command card sobe para a primeira dobra, o hero perde peso editorial, os pills encurtam e
	a altura total do topo cai de forma perceptível
- em breakpoints intermediários, `metric-grid` e `service-grid` deixam de colapsar cedo demais e preservam
	duas colunas onde ainda faz sentido
- em telas largas e ultra-wide, o container principal e os grids usam mais largura útil e reduzem áreas
	mortas visíveis no layout
- os metadados do topo agora passam por helpers responsivos em JS (`refreshTopMetaPills`) para adaptar a
	cópia conforme viewport e reaplicar a compactação em resize

## Validação

- `get_errors` em `apps/rs-observability-api/web/index.html`: sem erros
- deploy OCI executado com `apps/rs-observability-api/deploy.sh` e rollout estável do
	`rs-observability-api-deployment` em `default`
- `https://reports.dnor.io/` respondeu `HTTP 200` após o rollout e o HTML público passou a expor os markers
	`refreshTopMetaPills` e `Snapshot ·`
- `https://reports.dnor.io/api/live/overview` permaneceu coerente, com payload `available: true`, cobertura
	crítica saudável e nós prontos reportados pela própria tela
- novas capturas geradas em `.qa/reports/ui-audit/mobile-polish.png`, `.qa/reports/ui-audit/desktop-polish.png`
	e `.qa/reports/ui-audit/wide-polish.png`

## Risco residual

- o certificado atual de `reports.dnor.io` continua com problema de cadeia/issuer no cliente de validação,
	então os checks automatizados seguiram usando `curl -k` e Chrome com `--ignore-certificate-errors`
