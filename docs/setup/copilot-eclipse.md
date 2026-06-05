# Copilot no Eclipse EE + Monitoria no agent-meter

Guia objetivo para sair do zero com um projeto de teste no Eclipse EE e validar observabilidade no agent-meter (modelo APM para IDE/CLI via OTLP).

## 1) Pré-requisitos

- Eclipse IDE for Enterprise Java and Web Developers (2024-12+ recomendado)
- Java 21+
- Maven 3.9+
- Git
- Endpoint OTLP do collector publicado:
  - Produção: `https://agent-meter.dnor.io/v1/traces`

## 2) Instalar o GitHub Copilot no Eclipse

1. Abra `Help > Eclipse Marketplace`.
2. Busque por `GitHub Copilot`.
3. Instale o plugin oficial.
4. Reinicie o Eclipse.
5. Faça login da sua conta GitHub no assistente do Copilot.

Observação:
- O parser do agent-meter já reconhece Eclipse por `user-agent` (`eclipse`/`jdt`) e por `service.name` contendo `eclipse`.

## 3) Configurar variáveis de OTEL no Eclipse

No Eclipse:
1. `Run > Run Configurations...`
2. Selecione sua configuração Java (App/Test).
3. Aba `Environment`.
4. Adicione:

- `OTEL_EXPORTER_OTLP_ENDPOINT=https://agent-meter.dnor.io`
- `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`
- `OTEL_SERVICE_NAME=eclipse-copilot`
- `OTEL_RESOURCE_ATTRIBUTES=deployment.environment=dev,service.namespace=ide,service.version=1.0.0`

Dica:
- Para flows de chat/tool, manter `OTEL_SERVICE_NAME=eclipse-copilot` ajuda na classificação e filtros.

## 4) Criar projeto teste (Maven)

No Eclipse:
1. `File > New > Maven Project`
2. GroupId: `io.dnor`
3. ArtifactId: `copilot-eclipse-sandbox`
4. Java: 21

Estrutura mínima:

- `src/main/java/io/dnor/App.java`
- `src/test/java/io/dnor/AppTest.java`

`App.java` exemplo:

```java
package io.dnor;

public class App {
    public static void main(String[] args) {
        System.out.println("copilot-eclipse-sandbox up");
    }
}
```

`AppTest.java` exemplo:

```java
package io.dnor;

import static org.junit.jupiter.api.Assertions.assertTrue;
import org.junit.jupiter.api.Test;

class AppTest {
    @Test
    void smoke() {
        assertTrue(true);
    }
}
```

## 5) Validar tráfego para o agent-meter

Com o projeto aberto no Eclipse:
1. Use o Copilot no editor (chat e sugestão de código).
2. Execute a aplicação e os testes pela Run Configuration com as variáveis OTEL.
3. Aguarde 10-30s.
4. Acesse `https://agent-meter.dnor.io`.
5. Verifique:
   - Dashboard `By Agent / IDE` com entrada de Eclipse
   - Conversas/eventos com `tool_name` e `llm_chat`

## 6) Checklist de monitoria (APM-like)

No agent-meter, confirme:
- `ide`: `copilot-eclipse`
- `tool_name`: eventos de ferramenta (ex. `read_file`) e `llm_chat`
- `trace_id` / `span_id` / `parent_span_id`
- `model`, `reasoning_tokens` (quando disponível), `finish_reason`
- `conversation_id` consistente para agrupamento

## 7) Regressão automática no repositório

Este fluxo já está no harness:
- Script dedicado:
  - `apps/agent-meter/scripts/validate_copilot_eclipse.sh`
- Harness completo:
  - `apps/agent-meter/scripts/validate_all_agents.sh`
- Teste de regressão:
  - `test_otlp_eclipse_copilot_execute_tool_and_chat` em `apps/agent-meter/crates/collector/tests/otlp_regression.rs`
- CI:
  - `.github/workflows/agent-meter-validation.yml`

## 8) Troubleshooting rápido

- Sem eventos no dashboard:
  - confira `OTEL_EXPORTER_OTLP_ENDPOINT`
  - teste conectividade HTTPS
  - valide se a Run Configuration usada no Eclipse recebeu as variáveis
- Eventos sem classificação Eclipse:
  - confirme `OTEL_SERVICE_NAME=eclipse-copilot`
  - confira user-agent `eclipse`/`jdt`
- Erro intermitente no push/deploy (registry local):
  - reabrir túnel SSH da porta `31444`
  - repetir deploy após validar `curl http://127.0.0.1:31444/v2/` (401 esperado)
