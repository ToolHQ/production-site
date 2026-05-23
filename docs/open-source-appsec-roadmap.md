# Roadmap Futuro - Plataforma AppSec Open Source (base equivalente ao GitHub CodeQL/GHAS)

## Status

- Horizonte: futuro (nao executar agora)
- Tipo: planejamento separado das demandas principais
- Objetivo: construir base AppSec open source com alta cobertura, custo previsivel e governanca

## Contexto e Limite Realista

- Meta realista: 80-90% de cobertura funcional comparada ao stack gerenciado do GitHub.
- Nao-meta inicial: paridade 100% com UX nativa de Security tab, triage e automacoes proprietarias.
- Restricao tecnica ja validada: CodeQL default setup em linux/arm64 nao e suportado para o fluxo atual.

## Escopo Funcional Alvo

1. SAST multi-linguagem (PR + full scan agendado).
2. SCA de dependencias e SBOM.
3. Secret scanning em PR e repositorio.
4. Gate de policy por severidade e contexto.
5. Triage centralizado com ownership, SLA e deduplicacao.
6. Metricas executivas (abertos, MTTR, tendencia, risco por repositorio).

## Matriz Inicial (Funcao -> Stack Open Source)

1. SAST geral: Semgrep OSS + regras custom.
2. JS/TS: ESLint security plugins + Semgrep.
3. Python: Bandit + Semgrep.
4. Rust: cargo-audit + clippy + Semgrep (regras focalizadas).
5. Shell: shellcheck + shfmt + Semgrep shell.
6. YAML/K8s: yamllint + kubeconform + conftest (OPA).
7. SCA/SBOM: OSV-Scanner + Syft/Grype ou Trivy.
8. Secrets: Gitleaks.
9. Consolidador de findings: DefectDojo (ou backend interno SARIF/JSON).

## Roadmap por Fases

### Fase 0 - Descoberta e Baseline (1-2 semanas)

1. Inventariar linguagens e superficies por pasta do repositorio.
2. Definir severidades, excecoes e politica minima de bloqueio.
3. Criar baseline inicial para reduzir ruido de legado.

Entregaveis:

- Matriz de cobertura por stack do repositorio.
- Politica de gate v1 (PR vs schedule).
- Lista de gaps de paridade com GHAS.

### Fase 1 - Pipeline Minimo Viavel (2-3 semanas)

1. Integrar Semgrep, Gitleaks e OSV/Trivy em workflow dedicado.
2. Publicar artefatos padronizados (SARIF/JSON) por job.
3. Ativar gates de severidade alta/critica em PR.

Entregaveis:

- Workflow AppSec OSS v1.
- Gate PR ativo para achados criticos.
- Relatorio de falso-positivo inicial.

### Fase 2 - Governanca e Triage (2-4 semanas)

1. Subir DefectDojo (ou camada interna equivalente) para consolidacao.
2. Deduplicacao, SLA por severidade e ownership por componente.
3. Dashboard de tendencia e risco por servico.

Entregaveis:

- Painel de triage unico.
- Fluxo de excecao com auditoria.
- SLO de remediacao por severidade.

### Fase 3 - Profundidade e Qualidade (3-6 semanas)

1. Regras custom por dominio (K8s, deploy, scripts, backend).
2. Scans noturnos full e PR scans leves orientados a paths.
3. Playbooks para reduzir falso-positivo sem perder cobertura.

Entregaveis:

- Rulepacks internos v1.
- Runbooks operacionais de AppSec.
- Indicadores de qualidade do scanner.

### Fase 4 - Maturidade (continuo)

1. Revisao trimestral de cobertura x incidentes reais.
2. Ajuste de gates por risco e impacto em produtividade.
3. Comparativo periodico open source vs GHAS para decisoes de custo.

Entregaveis:

- Review trimestral executivo.
- Plano de evolucao sem lock-in.

## KPI/SLO Sugeridos

1. Cobertura de scan em PR: >= 95% das mudancas relevantes.
2. MTTR critico/alto: <= 7 dias corridos.
3. Falso-positivo: <= 20% no trimestre apos calibracao.
4. Tempo extra de CI por PR: <= 6 minutos no perfil padrao.
5. SBOM por build principal: 100% dos artefatos deployaveis.

## Riscos e Mitigacoes

1. Risco: ruido alto no inicio.
   Mitigacao: baseline + rollout progressivo por severidade.
2. Risco: custo operacional da plataforma.
   Mitigacao: comecar lean e automatizar triage/reports.
3. Risco: lacunas em dataflow complexo.
   Mitigacao: combinar ferramentas por linguagem e regras internas.
4. Risco: queda de produtividade em PR.
   Mitigacao: scans path-aware e profile leve em PR.

## Decisoes Guardadas para Futuro

1. Manter CodeQL em hosted x64 enquanto ARM64 nao suportar o fluxo.
2. Priorizar stack open source como base principal para custo previsivel.
3. Reavaliar paridade total apenas apos maturidade da Fase 3.

## Checklist de Inicio (quando priorizar)

- [ ] Aprovar owner do programa AppSec OSS.
- [ ] Definir budget operacional mensal e janela de rollout.
- [ ] Escolher consolidador (DefectDojo vs interno).
- [ ] Criar epic no KANBAN com fases e criterios de pronto.
- [ ] Iniciar Fase 0 com baseline medido.
