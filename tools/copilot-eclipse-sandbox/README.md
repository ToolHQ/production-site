# copilot-eclipse-sandbox

Projeto Eclipse pronto para uso com GitHub Copilot + monitoria OTLP no agent-meter.

## Como usar (Windows)

### 1. Rodar o setup (uma vez)

Abra PowerShell na pasta deste projeto e execute:

```powershell
.\setup.ps1
```

Ou via Git Bash:

```bash
bash setup.sh
```

Isso vai:

- Baixar o OpenTelemetry Java Agent para `lib/`
- Validar Java 17+ e Maven
- Compilar o projeto e baixar dependências

### 2. Importar no Eclipse

1. `File > Import > Existing Maven Projects`
2. Aponte para esta pasta
3. `Finish`

### 3. Rodar

Duas Run Configurations já estão incluídas:

- **copilot-eclipse-sandbox** — roda `App.main()` com OTEL ativo
- **copilot-eclipse-sandbox-tests** — roda todos os JUnit 5 com OTEL ativo

Basta ir em `Run > Run Configurations` e escolher uma delas.

### 4. Validar no agent-meter

1. Abra https://agent-meter.dnor.io
2. Vá em Reports
3. Confirme a linha `copilot-eclipse` no relatório By Agent/IDE

## Estrutura

```
.classpath              — Eclipse build path (JavaSE-17)
.project                — Eclipse project descriptor (Maven + Java)
.settings/              — Eclipse compiler settings (Java 17)
lib/                    — OpenTelemetry Java Agent (gerado pelo setup)
pom.xml                 — Maven: Java 17, JUnit 5, Surefire
src/main/java/          — App.java
src/test/java/          — AppTest.java (4 testes)
*.launch                — Run Configurations pré-configuradas
setup.ps1               — Setup automático (PowerShell)
setup.sh                — Setup automático (Bash)
```

## Variáveis OTEL pré-configuradas nos .launch

| Variável                    | Valor                                                                  |
| --------------------------- | ---------------------------------------------------------------------- |
| OTEL_EXPORTER_OTLP_ENDPOINT | https://agent-meter.dnor.io                                            |
| OTEL_EXPORTER_OTLP_PROTOCOL | http/protobuf                                                          |
| OTEL_TRACES_EXPORTER        | otlp                                                                   |
| OTEL_SERVICE_NAME           | eclipse-copilot                                                        |
| OTEL_RESOURCE_ATTRIBUTES    | deployment.environment=dev,service.namespace=ide,service.version=1.0.0 |
