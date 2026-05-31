# T-326: DNOR shell — largura de leitura em todas as views (ultra-wide)

- **Status**: Backlog
- **Priority**: 🔵 Medium
- **Owner**: Cursor / AI Radar
- **Epic**: Node Fleet v2 / reports.dnor.io (T-301)
- **Est**: 3h
- **Depends on**: T-325 (padrão estabelecido no Copilot)
- **Blocks**: Nenhum

## Context

T-325 limita `#fleet-copilot` a ~1200px. **Overview, Nodes, Intel, Incidents** ainda usam `main { max-width: 1480px }` + tabelas full-bleed — em ultrawide a leitura horizontal continua ruim.

## Escopo

- [ ] Token CSS global `--dnor-content-max: 1280px` (ou 1200px) em `index.css`
- [ ] `.shell` children: panels, tables, masthead — `max-width` + `margin-inline: auto` onde fizer sentido
- [ ] NodesPanel / FleetOverviewTable: não esticar colunas com `1fr` infinito em viewports >1800px
- [ ] Validar 1920px + 3440×1440 + mobile

## Fora de escopo

- Redesign completo T-301

## Referências

- [T-325](T-325-Fleet-Copilot-UltraWide-Max-Width.md)
- [T-301](T-301-Node-Fleet-v2-UI-mockup-DNOR-period-export-done.md)
