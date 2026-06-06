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

### Jenkins (genérico — readJSON + stage dinâmico)

Groovy **não** conhece os stages. Loop (JsonSlurper — sem plugin readJSON):

```groovy
def after = ''
while (true) {
  def step = new groovy.json.JsonSlurper().parseText(sh(returnStdout: true, script: 'citools next --json ...').trim())
  if (step.done) break
  stage(step.stageName) {
    sh "citools run '${step.id}'"
  }
  after = step.id
}
```

Manifesto completo (preview / debug):

```bash
citools export-json | jq .
```

Ver [components/ssdnodes/jenkins/Jenkinsfile.generic](../../components/ssdnodes/jenkins/Jenkinsfile.generic).

## Roadmap

### Quality (T-341 — feito / em PR)
- [x] `pipeline.yaml` + Jenkinsfile.generic
- [x] Migração GHA quality/codeql/auto-docs

### Deploy program (T-344 — backlog)
- [ ] `deploy-catalog.yaml` + `citools deploy list|plan|run`
- [ ] Workers: Hetzner buildx, target OCI, target SSDNodes
- [ ] Jenkins job `deploy-apps` (param APP + TARGET)
- [ ] Branch protection `jenkins/citools` + webhook

Ver [tasks/CITOOLS-DEPLOY-BACKLOG.md](../../tasks/CITOOLS-DEPLOY-BACKLOG.md) e [ADR deploy workers](../../components/ssdnodes/ADR-citools-deploy-workers.md).

### Quality (futuro)
- [ ] `citools run verify-changed` nativo (sem delegar ao bash)
- [ ] Relatório JSON (`--report /tmp/citools-report.json`)
- [ ] Cache de artefactos entre stages
