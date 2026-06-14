# Tutorial Completo: Como Conectar o Copilot no Eclipse EE e Monitorar no agent-meter

Este tutorial foi escrito para quem nunca fez essa configuração antes.
Objetivo: sair do zero e terminar com um projeto Java funcionando no Eclipse, com eventos aparecendo no agent-meter.

Tempo médio:

- Instalação e login: 10 a 20 minutos
- Projeto de teste: 10 minutos
- Configuração de monitoria: 5 minutos
- Validação final: 5 minutos

---

## 1. O que você vai ter ao final

Ao concluir este passo a passo, você terá:

- Eclipse EE com GitHub Copilot instalado e autenticado.
- Um projeto Java de teste criado e executando.
- Telemetria OTLP enviada para o agent-meter.
- Evidência no dashboard de que o tráfego do Eclipse está sendo monitorado.

---

## 2. Pré-requisitos (confira antes de começar)

Você precisa de:

- Eclipse IDE for Enterprise Java and Web Developers (recomendado 2024-12 ou superior).
- Java 21 ou superior.
- Maven 3.9 ou superior.
- Conta GitHub com acesso ao Copilot.
- Acesso ao endpoint de monitoria:
  - https://agent-meter.dnor.io

Checklist rápido:

- O Eclipse abre normalmente.
- O comando java -version funciona no seu computador.
- O comando mvn -v funciona no seu computador.
- Você consegue abrir https://agent-meter.dnor.io no navegador.

---

## 3. Instalar o GitHub Copilot no Eclipse (passo a passo)

1. Abra o Eclipse.
2. No menu superior, clique em Help.
3. Clique em Eclipse Marketplace.
4. No campo de busca, digite GitHub Copilot.
5. Selecione o plugin oficial do GitHub.
6. Clique em Install.
7. Aceite os termos da instalação.
8. Aguarde o download e a instalação.
9. Reinicie o Eclipse quando solicitado.

Depois da reinicialização:

1. Faça login com sua conta GitHub.
2. Autorize o Eclipse a usar o Copilot.
3. Aguarde a confirmação de que a extensão está ativa.

Sinal de sucesso:

- O Copilot aparece habilitado no Eclipse.

---

## 4. Criar um projeto Java de teste no Eclipse

1. Clique em File.
2. Clique em New.
3. Clique em Maven Project.
4. Escolha criar projeto simples (sem archetype complexo), se solicitado.
5. Preencha:
   - Group Id: io.dnor
   - Artifact Id: copilot-eclipse-sandbox
   - Version: 1.0.0-SNAPSHOT
6. Finalize o assistente.

Agora crie os arquivos:

- src/main/java/io/dnor/App.java
- src/test/java/io/dnor/AppTest.java

Conteúdo de App.java:

```java
package io.dnor;

public class App {
    public static void main(String[] args) {
        System.out.println("copilot-eclipse-sandbox up");
    }
}
```

Conteúdo de AppTest.java:

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

Sinal de sucesso:

- O projeto compila sem erro.
- O teste smoke executa com sucesso.

### 4.1 Correção guiada (se aparecer erro de JUnit ou JavaSE-1.8)

Se você estiver vendo erros como:

- Test cannot be resolved to a type
- The import org.junit.Test cannot be resolved
- Build path specifies execution environment JavaSE-1.8

Faça exatamente nesta ordem.

Passo 1: Ajustar o pom.xml para Java 21 + JUnit 5

Substitua o conteúdo do pom.xml por este modelo mínimo:

```xml
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <groupId>io.dnor</groupId>
  <artifactId>copilot-eclipse-sandbox</artifactId>
  <version>1.0.0-SNAPSHOT</version>

  <properties>
    <maven.compiler.release>21</maven.compiler.release>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    <junit.jupiter.version>5.10.2</junit.jupiter.version>
  </properties>

  <dependencies>
    <dependency>
      <groupId>org.junit.jupiter</groupId>
      <artifactId>junit-jupiter</artifactId>
      <version>${junit.jupiter.version}</version>
      <scope>test</scope>
    </dependency>
  </dependencies>

  <build>
    <plugins>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-surefire-plugin</artifactId>
        <version>3.2.5</version>
      </plugin>
    </plugins>
  </build>
</project>
```

Passo 2: Garantir import correto no AppTest.java

Use estes imports (JUnit 5):

```java
import static org.junit.jupiter.api.Assertions.assertEquals;
import org.junit.jupiter.api.Test;
```

Se existir org.junit.Test ou org.junit.Assert, troque para o formato acima.

Passo 3: Corrigir JDK do projeto no Eclipse

1. Clique com botão direito no projeto.
2. Clique em Properties.
3. Vá em Java Build Path > Libraries.
4. Remova a entrada JRE System Library [JavaSE-1.8], se existir.
5. Clique em Add Library > JRE System Library.
6. Escolha Workspace default JRE (Java 21) ou Alternate JRE com Java 21.
7. Aplique e feche.

Passo 4: Corrigir nível de compilação

1. Properties > Java Compiler.
2. Defina Compiler compliance level para 21.
3. Aplique.

Passo 5: Forçar atualização do Maven

1. Clique com botão direito no projeto.
2. Maven > Update Project...
3. Marque Force Update of Snapshots/Releases.
4. Clique em OK.

Passo 6: Limpar build

1. Menu Project > Clean...
2. Selecione o projeto.
3. Execute o clean.

Resultado esperado:

- Os erros de org.junit e Test somem.
- O AppTest roda pelo JUnit sem falha de dependência.

---

## 5. Configurar monitoria OTLP no Eclipse

Este é o passo mais importante para os dados aparecerem no agent-meter.

A telemetria é emitida pelo plugin Copilot do Eclipse (não pela sua app Java).
Para que o plugin enxergue as variáveis OTEL, elas precisam estar no ambiente
do processo Eclipse — não em Run Configurations da sua aplicação.

### 5.1 Opção recomendada: usar o script start-eclipse-otel.bat (Windows)

Na pasta do projeto (`tools/copilot-eclipse-sandbox/`) já existe um arquivo pronto:

```
start-eclipse-otel.bat
```

1. Copie esse arquivo para a área de trabalho do Windows.
2. Edite a linha `ECLIPSE_PATH=` e coloque o caminho real do seu eclipse.exe.
3. Use esse atalho para abrir o Eclipse (sempre).

O que ele faz:

- Define todas as variáveis OTEL no ambiente.
- Abre o Eclipse com essas variáveis ativas.
- O plugin Copilot herda automaticamente e emite traces para o agent-meter.

### 5.2 Opção alternativa: variáveis de ambiente do sistema (permanente)

Se preferir não usar o .bat, defina nas variáveis de ambiente do Windows:

1. Tecla Windows > pesquise "Variáveis de Ambiente" > abra.
2. Em "Variáveis do sistema", clique em "Novo" para cada uma:

| Variável                    | Valor                                                                  |
| --------------------------- | ---------------------------------------------------------------------- |
| OTEL_EXPORTER_OTLP_ENDPOINT | https://agent-meter.dnor.io                                            |
| OTEL_EXPORTER_OTLP_PROTOCOL | http/protobuf                                                          |
| OTEL_TRACES_EXPORTER        | otlp                                                                   |
| OTEL_SERVICE_NAME           | eclipse-copilot                                                        |
| OTEL_RESOURCE_ATTRIBUTES    | deployment.environment=dev,service.namespace=ide,service.version=1.0.0 |

3. Feche e reabra o Eclipse.

### 5.3 Verificar que funcionou

Após abrir o Eclipse com as variáveis ativas:

1. Abra qualquer arquivo Java.
2. Use o Copilot (sugestão inline ou chat).
3. Aguarde 30 segundos.
4. Abra https://agent-meter.dnor.io e vá em Reports.
5. Confirme que `copilot-eclipse` aparece na lista By Agent/IDE.

Sinal de sucesso:

- A linha `copilot-eclipse` existe no relatório com pelo menos 1 call.

---

## 6. Gerar atividade real no Copilot (para criar eventos)

Com o projeto aberto no Eclipse (iniciado via start-eclipse-otel.bat):

1. Abra App.java.
2. Peça uma sugestão para o Copilot no editor.
3. Use o chat do Copilot para pedir uma melhoria simples.
4. Aceite pelo menos uma sugestão do Copilot.
5. Execute a aplicação (Run as Java Application).
6. Execute os testes (Run as JUnit Test).

Dica:

- Faça de 2 a 3 interações com o Copilot para gerar mais dados de validação.
- O javaagent NÃO é necessário para o Copilot emitir traces.
  Ele é útil apenas se você quiser instrumentar a própria aplicação Java.

---

## 7. Validar no dashboard do agent-meter

1. Abra https://agent-meter.dnor.io no navegador.
2. Aguarde de 10 a 30 segundos após rodar a aplicação/testes.
3. Vá para os relatórios do dashboard.
4. Verifique a seção By Agent / IDE.
5. Confirme que há tráfego associado ao Eclipse/Copilot.

Você deve encontrar campos como:

- ide: copilot-eclipse
- tool_name: eventos de ferramenta e chat
- trace_id e span_id
- model e finish_reason (quando disponíveis)
- conversation_id para agrupamento

Sinal de sucesso:

- O uso do Copilot no Eclipse aparece como evento no monitoramento.

---

## 8. Checklist de aceite (para publicação no produto)

Marque tudo antes de considerar configuração concluída:

- Copilot instalado no Eclipse.
- Login do GitHub concluído no plugin.
- Projeto de teste criado e compilando.
- Variáveis OTLP configuradas na Run Configuration.
- Interações de Copilot realizadas no projeto.
- Aplicação e testes executados.
- Eventos visíveis no dashboard do agent-meter.

Se todos os itens estiverem marcados, o ambiente está pronto para uso.

---

## 9. Erros comuns e como resolver

### 9.1 Não aparece nada no dashboard

Verifique na ordem:

1. Endpoint está correto: https://agent-meter.dnor.io
2. Protocolo está correto: http/protobuf
3. Run Configuration ativa é a mesma onde você adicionou as variáveis.
4. Você realmente executou app/testes depois da configuração.

### 9.2 Eventos aparecem, mas sem classificação de Eclipse

Verifique:

1. OTEL_SERVICE_NAME está exatamente eclipse-copilot.
2. Você está usando o Eclipse com plugin oficial do Copilot.

### 9.3 Copilot não responde no Eclipse

Verifique:

1. Conta GitHub autenticada no plugin.
2. Licença/acesso ao Copilot ativo na conta.
3. Reinicie o Eclipse e tente novamente.

### 9.4 Erro de JUnit e JavaSE-1.8 ao mesmo tempo

Sintoma típico:

- 6 erros no AppTest.java com import org.junit não resolvido.
- Warnings sobre JavaSE-1.8 e compiler compliance 1.8.

Causa:

- Projeto criado em modo legado (JUnit 4/Java 1.8) sem dependências compatíveis.

Solução:

- Execute a seção 4.1 completa deste guia, sem pular etapas.

---

## 10. Validação técnica automatizada (time interno)

Além da validação manual para usuários, o repositório já possui cobertura automatizada:

- Script dedicado Eclipse:
  - apps/agent-meter/scripts/validate_copilot_eclipse.sh
- Harness geral:
  - apps/agent-meter/scripts/validate_all_agents.sh
- Regressão OTLP:
  - apps/agent-meter/crates/collector/tests/otlp_regression.rs
- Fixture Eclipse:
  - apps/agent-meter/crates/collector/tests/fixtures/eclipse_copilot_execute_tool.json
- Workflow CI:
  - .github/workflows/agent-meter-validation.yml

---

## 11. FAQ para usuário leigo

Preciso entender OpenTelemetry para usar?

- Não. Basta copiar as variáveis corretamente.

Posso usar outro nome de serviço?

- Pode, mas o recomendado é eclipse-copilot para manter consistência de monitoria.

Quanto tempo demora para aparecer no dashboard?

- Em geral entre 10 e 30 segundos.

Se eu errar alguma variável, quebra meu projeto?

- Não quebra o projeto Java. Só impede o envio correto da monitoria.

---

## 12. Encerramento

Se você chegou até aqui e validou os eventos no dashboard, sua integração está pronta.
Você já pode usar este mesmo padrão para outros projetos no Eclipse, mantendo as variáveis OTLP e o fluxo de validação.
