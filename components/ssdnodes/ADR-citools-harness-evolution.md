# ADR: citools — evolução do harness CI (T-341+)

**Status:** Proposed (MVP em `tools/citools`)  
**Data:** 2026-06-05  
**Relacionado:** T-141 (Harness), T-341 (Jenkins + Sonar SSDNodes)

## Contexto

O monorepo hoje usa:

1. **GitHub Actions** — quality gates por path, CodeQL
2. **`tools/harness/verify.sh`** — gates shell locais
3. **Jenkins SSDNodes** — recém-deployado (orquestrador, zero SaaS)

Duplicar lógica entre GHA, shell e Jenkins aumenta drift. Queremos **um contrato de stages** que qualquer orchestrator execute.

## Decisão

Introduzir **`citools`** (CLI Rust) + **`pipeline.yaml`** declarativo:

```
pipeline.yaml  →  citools run-all  ←  Jenkinsfile.generic (1 stage Groovy)
                              ↑
                              └──  GHA / local dev / futuro Drone
```

### Princípios

1. **Agnóstico** — Jenkins não conhece clippy/eslint/harness; só chama `citools`.
2. **Gradual** — stages começam delegando ao shell existente; migram para Rust nativo quando estável.
3. **Reprodutível** — mesmo comando local e no agent Jenkins.
4. **Zero custo** — binário estático no agent; Sonar CE self-hosted.

### Formato pipeline.yaml (v1)

```yaml
version: 1
name: production-site-default
stages:
  - id: verify-changed
    run: ./tools/harness/verify.sh verify-changed
  - id: sonar-scan
    when: env:SONAR_TOKEN
    run: ./tools/citools/scripts/sonar-scan.sh
```

### Jenkinsfile genérico

Ver `components/ssdnodes/jenkins/Jenkinsfile.generic` — único job multibranch; stages não são editados em Groovy.

## Consequências

| Positivo | Negativo / mitigação |
|----------|----------------------|
| Um lugar para gates | MVP ainda delega shell — OK fase 1 |
| Local = CI | Precisa Rust no agent (imagem `rust:1.88`) |
| Sonar integrável via stage | Token `sonar-token` manual até JCasC |
| GHA pode chamar citools depois | Migrar workflow em PR separado |

## Fases

| Fase | Entrega |
|------|---------|
| **0 (este PR)** | citools MVP, pipeline.yaml, Jenkinsfile.generic, deploy live T-341 |
| **1** | Job multibranch Jenkins apontando para repo |
| **2** | `citools verify-changed` nativo (port do harness bash) |
| **3** | Relatório JSON + quality gate Sonar |
| **4** | GHA chama `citools run-all` no runner ssdnodes (substituir duplicação) |

## Referências

- [tools/citools/README.md](../../../tools/citools/README.md)
- [components/ssdnodes/jenkins/pipeline.yaml](jenkins/pipeline.yaml)
- [T-341](../tasks/2026/Q2/T-341-SSDNodes-Jenkins-SonarQube-Platform.md)
