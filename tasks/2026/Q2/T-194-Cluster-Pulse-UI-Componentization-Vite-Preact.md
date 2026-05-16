# T-194: Cluster Pulse UI Componentization (Vite + Preact)

- **Status**: In Progress
- **Priority**: 🔼 High
- **Epic/Owner**: Antigravity
- **Estimation**: 4h

## Context
O arquivo `index.html` monolítico de 74KB do **Cluster Pulse** (apps/rs-observability-api/web) cresceu ao ponto de tornar a adição de novos recursos arriscada.
Como primeiro passo do [Roadmap do Cluster Pulse](ROADMAP-CLUSTER-PULSE.md), precisamos modernizar o front-end sem aumentar o uso de recursos. A stack `Vite + Preact (TS)` foi escolhida para componentizar o UI, preservando a estética de `ui-ux-excellence` e o footprint quase zero.

## Tasks
- [x] Inicializar boilerplate Vite + Preact no diretório `apps/rs-observability-api/web-v2`.
- [x] Portar o HTML base e o arquivo CSS premium original para App.tsx e style.css.
- [ ] Quebrar os elementos repetitivos (ServiceCard, CommandCard, ArtifactRow, MetricSparkline) em componentes Preact.
- [ ] Portar o script JS de polling (live/overview) usando hooks simples (useEffect).
- [ ] Testar build local, confirmar tamanho de bundle e preparar deploy OCI via substituição do `/web` original pelo gerado no `dist/`.

## Validação
# TODO: Registre comandos reais executados e o resultado objetivo.
# Para mudança de código, o mínimo esperado é o comando root path-aware quando aplicável:
# - ./tools/harness/verify.sh verify-changed --paths <arquivos alterados>
