# T-139: Observability Console Ultrawide UX and Text Visibility Pass

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: DevExp / Observability
- **Estimation**: 3h

## Context
O console já melhorou bastante nas passadas T-135/T-137, mas o uso real em monitor ultra-wide ainda
mostra dois problemas claros:

- em telas muito largas, a home continua com área morta demais nas laterais e densidade insuficiente para
	um operador que quer aproveitar 21:9 ou 32:9
- no bloco `Critical services`, algumas rotas e métricas ficam espremidas a ponto de parecerem “sumir” ou
	perder legibilidade, especialmente quando o card recebe quatro blocos estatísticos lado a lado

O diagnóstico desta task foi aberto com base em dois prints do usuário e uma inspeção complementar via MCP
no endpoint real `reports.dnor.io`. O browser MCP ainda não confia na CA interna por padrão, então a
inspeção exigiu atravessar o interstitial manualmente, mas a página carregou e permitiu medições objetivas.

### Achados confirmados

- em viewport `2560x1400`, o `main` usa `1880px`, então ainda sobra muita margem visual em monitores bem
	largos para um console que deveria assumir densidade operacional mais agressiva
- no mesmo viewport, o `service-grid` fica com largura útil de ~`1175px` e 4 colunas, produzindo cards com
	~`283px` cada
- os `service-card`s usam `overflow: hidden` e a linha `.stat-row` continua em flex horizontal rígido,
	com quatro `stat-stack`s competindo pela mesma faixa curta
- a sonda via MCP encontrou `scrollWidth > clientWidth` em `service-card`s como `Nexus Registry`,
	`Coroot UI` e `Longhorn Manager`, o que confirma clipping horizontal real e não só impressão visual

### Hipótese local

O problema principal não é falta de breakpoint para ultra-wide isoladamente. O gargalo é a combinação de:

- `service-grid` agressivo demais em `@media (min-width: 1880px)` com `repeat(4, minmax(0, 1fr))`
- `service-card { overflow: hidden; }`
- `.stat-row` em `display: flex` com `justify-content: space-between`, forçando o `primary route` a dividir
	espaço com mais três métricas mesmo quando a rota é longa

### Arquivo central

- `apps/rs-observability-api/web/index.html`

## Tasks
- [x] Reproduzir o problema com prints do usuário e inspeção MCP em viewport ultra-wide
- [x] Redefinir a estratégia de largura e densidade para `>= 1880px`, pensando explicitamente em monitores ultra-wide
- [x] Corrigir a composição interna dos `service-card`s para que `primary route` e labels nunca sejam truncados visualmente
- [x] Auditar outros blocos com risco semelhante de clipping usando probe de overflow via MCP/JS
- [x] Validar novamente em ultra-wide com MCP e screenshots atualizados
- [x] Publicar no cluster e registrar o fechamento da task

## Entrega

- o `main` ganhou uma estratégia mais agressiva para monitores ultra-wide, com novo degrau em `>= 2200px`
	e melhor redistribuição entre `main-stack` e `rail-stack`
- o bloco `Critical services` deixou de usar 4 cards estreitos em ultra-wide e passou a operar com cards bem
	mais largos, reduzindo área morta sem sacrificar legibilidade
- a linha interna de métricas dos `service-card`s foi reestruturada para que a rota primária vire uma linha
	dedicada (`route-stack`) em vez de disputar espaço com os contadores de readiness/running/restarts
- rotas, subtitles e mensagens passaram a usar wrapping explícito (`overflow-wrap:anywhere` / `word-break`)
	para eliminar o comportamento em que o texto parecia “sumir” no fim do card

## Validação

- `get_errors` em `apps/rs-observability-api/web/index.html`: sem erros
- deploy executado com `apps/rs-observability-api/deploy.sh` e rollout estável do
	`rs-observability-api-deployment` em `default`
- inspeção MCP em `2560x1400` confirmou `mainWidth: 2320`, `serviceGridWidth: 1692` e cards de serviço com
	~`555px` de largura
- a sonda MCP pós-fix encontrou `route-stack` presente e `clipped: []` no bloco `Critical services`
- a auditoria global de overflow/clipping no viewport ultra-wide voltou com `offenderCount: 0`
- capturas geradas em `.qa/reports/ui-audit/mcp-ultrawide-postfix-v2.png` e
	`.qa/reports/ui-audit/mcp-critical-services-postfix-v2.png`

## Observação operacional

- o browser do MCP ainda não herdou a trust chain local desta workstation; para a inspeção real do endpoint
	foi necessário atravessar o interstitial com o bypass manual do Chrome (`thisisunsafe`)
