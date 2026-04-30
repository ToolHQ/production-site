---
name: ui-ux-excellence
description: Protocolos de Design UI/UX Premium para Agentes. Diretrizes para densidade de dados, estética moderna, hierarquia visual e experiência operations-first.
---

# UI/UX Excellence Protocol

Este skill define o padrão de qualidade estética e de usabilidade (UX) para interfaces criadas ou modificadas neste repositório. O foco principal é a **excelência visual ("Premium Feel")** e **eficiência operacional** (data-dense dashboards).

Ao ser invocado para revisar, criar ou refatorar interfaces (HTML, CSS, JS, React, etc), você DEVE seguir estas diretrizes impreterivelmente.

## 1. Princípios Estéticos (The "Premium" Factor)

O usuário deve se impressionar com o visual (*wow factor*). Interfaces com aspecto de "MVP básico" são inaceitáveis.

- **Cores Harmônicas:** Evite cores primárias puras (ex: `#FF0000` para erro). Use paletas HSL balanceadas (ex: Tailwind-like slates, zincs, emeralds, roses). Suporte nativo a **Dark Mode** é quase sempre um requisito para dashboards.
- **Micro-interações:** Toda ação ou hover deve ter feedback visual sutil. Use transições suaves (`transition: all 0.2s ease-in-out`) em botões, links e cards.
- **Glassmorphism & Depth:** Substitua bordas sólidas pesadas por sombras suaves (`box-shadow`), gradientes muito leves e fundos translúcidos (`backdrop-filter: blur()`) quando o contexto exigir foco (ex: modais, sticky headers).
- **Tipografia Moderna:** Nunca use fontes padrão do navegador. Priorize fontes sem serifa modernas (Inter, Roboto, Outfit, Geist). Use pesos variados (Medium/Semibold) para criar hierarquia visual, não apenas tamanho.
- **Whitespace (Respiro):** Densidade de dados não significa caos. Use espaçamentos consistentes (base-8 ou base-4) para separar blocos lógicos.

## 2. Operations-First Dashboards (Data Heavy)

O "Observability Console" e ferramentas internas lidam com muitos dados. 

- **Progressive Disclosure:** Não vomite tudo na tela. Mostre os KPIs críticos no topo/esquerda (F-Pattern). Esconda detalhes granulares atrás de accordions, modais ou abas (Tabs).
- **Data-Ink Ratio:** Remova gridlines desnecessárias, bordas redundantes e fundos pesados em tabelas. A cor deve ser usada intencionalmente para sinalizar status (🟢 Saudável, 🟡 Alerta, 🔴 Crítico), não para decoração.
- **Tipografia Tabular:** Para métricas financeiras, IPs, ou contadores, use `font-variant-numeric: tabular-nums` para que os números não fiquem dançando quando atualizados em real-time.
- **Zero States & Skeletons:** Nunca deixe a tela "piscando" branca. Se houver delay, use skeleton loaders. Se não houver dados, mostre um "Empty State" elegante explicando por que está vazio.

## 3. Checklist de Heurísticas de Usabilidade (UX)

Antes de aprovar qualquer mudança de UI, faça o check mental:

1. **Visibilidade do Status:** O usuário sabe se a página está carregando? Sabe se o cluster está offline?
2. **Hierarquia Clara:** O CTA (Call to Action) principal é óbvio?
3. **Consistência:** Os botões primários têm o mesmo estilo em todo o app?
4. **Prevenção de Erros:** Ações destrutivas (ex: "Deletar Volume") exigem confirmação visual ou steps de segurança?
5. **Responsividade Tática:** Em telas estreitas, as colunas menos importantes da tabela desaparecem elegantemente em vez de quebrar o layout horizontal?

## 4. Como Executar um Review de UX neste Repo

1. **Analise o estado atual:** Leia o HTML/CSS/JS/TS alvo.
2. **Identifique fricções:** Procure por divs aninhadas excessivamente, inline styles pobres ou falta de CSS semântico/variáveis.
3. **Proponha Refatoração:** 
   - Aplique cores modernas e design system (variáveis CSS).
   - Adicione feedback interativo (hover, active, focus).
   - Otimize a tabela/grid de dados, ajustando alinhamento e hierarquia.
4. **Iteração:** Concentre-se em gerar componentes que causem "wow" e peçam o mínimo de esforço cognitivo do usuário para ler a métrica ou interagir.
