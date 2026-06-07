# T-350: agent-meter — Remove hardcoded pricing from HTML

- **Status**: To Do
- **Priority**: 🔼 High
- **Owner**: Copilot/VSCode
- **Estimate**: 2h

## Context

`pricing.html` tem os planos Free/Pro/Team com preços hardcoded ($0/$29/$99) diretamente no HTML.
Deveria vir de uma API (`/api/billing/plans`) ou de config, nunca inline no template.
A classe `.preview-mock` no dashboard preview SVG também precisa ser removida ou substituída por screenshot real.

## Tasks

- [ ] Criar endpoint `GET /api/billing/plans` que retorna os planos do DB ou config
- [ ] Mover definição de planos para `config` ou tabela `billing_plans`
- [ ] Refatorar `pricing.html` para consumir API em vez de HTML hardcoded
- [ ] Remover `.preview-mock` CSS class e substituir SVG por screenshot real do dashboard
- [ ] Testes: verificar que `/pricing` renderiza dinamicamente
