# citools — CI stage runner (Rust)

**Objetivo:** substituir gradualmente lógica espalhada em shell/GHA por um CLI único, **agnóstico ao orchestrator**. Jenkins (ou GHA) só chama `citools run-all`; os stages vivem em `pipeline.yaml`.

## Por quê

| Hoje | Alvo |
|------|------|
| Gates em shell + GHA duplicados | Stages declarativos em YAML |
| Jenkinsfile acoplado a comandos | Jenkinsfile genérico (1 stage Groovy) |
| Difícil reproduzir CI localmente | `citools run-all` = mesmo fluxo local/Jenkins |

Ver ADR: [components/ssdnodes/ADR-citools-harness-evolution.md](../../components/ssdnodes/ADR-citools-harness-evolution.md)

## Build

```bash
cd tools/citools
cargo build --release
# bin: target/release/citools
```

## Comandos

```bash
citools list --pipeline components/ssdnodes/jenkins/pipeline.yaml
citools plan --pipeline components/ssdnodes/jenkins/pipeline.yaml
citools run verify-changed --pipeline components/ssdnodes/jenkins/pipeline.yaml
citools run-all --pipeline components/ssdnodes/jenkins/pipeline.yaml
```

## pipeline.yaml

```yaml
version: 1
name: production-site-default
stages:
  - id: verify-changed
    description: Harness path-aware gates
    run: ./tools/harness/verify.sh verify-changed
  - id: sonar-scan
    when: env:SONAR_TOKEN
    run: ./tools/citools/scripts/sonar-scan.sh
```

## Jenkins (genérico)

```groovy
// components/ssdnodes/jenkins/Jenkinsfile.generic
sh 'citools run-all --pipeline components/ssdnodes/jenkins/pipeline.yaml'
```

## Roadmap

- [ ] `citools run verify-changed` nativo (sem delegar ao bash)
- [ ] Relatório JSON (`--report /tmp/citools-report.json`) para Sonar/Jenkins
- [ ] Cache de artefactos entre stages
- [ ] Integração Sonar scanner como stage built-in
