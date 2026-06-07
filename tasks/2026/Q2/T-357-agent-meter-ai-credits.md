# T-357: agent-meter — Pricing model: add AI Credits concept

- **Status**: To Do
- **Priority**: 🔼 High
- **Owner**: Copilot/VSCode
- **Estimate**: 3h

## Context

O Copilot CLI cobra em "AI Premium Requests" (créditos), não em USD direto por token.
O dashboard mostra custo em USD baseado em preço de API, mas para Copilot o custo real
é zero (incluso no plano) ou em créditos do plano GitHub.

Precisamos de um conceito dual: USD real (para Anthropic/OpenAI API direto) vs AI Credits
(para serviços tipo Copilot, Cursor Pro, etc. que cobram por subscription).

## Tasks

- [ ] Adicionar coluna `billing_model` na `model_pricing`: 'token' (padrão) ou 'credit'
- [ ] Adicionar coluna `credits_per_request` para modelos que cobram por request
- [ ] Para Copilot (service=copilot): calcular custo como N credits, não USD
- [ ] Separar no dashboard: "API Cost (USD)" vs "AI Credits Used"
- [ ] Na cost page: mostrar tab "Credits" com breakdown por IDE/agent
- [ ] Atualizar Cost API para retornar `total_credits` além de `total_usd`
- [ ] Documentar na docs page a diferença entre os dois modelos
