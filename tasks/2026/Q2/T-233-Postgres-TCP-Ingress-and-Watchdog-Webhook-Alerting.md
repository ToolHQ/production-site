# T-233: Postgres TCP Ingress and Watchdog Webhook Alerting

- **Status**: Done
- **Priority**: High
- **Epic/Owner**: Antigravity
- **Estimation**: 2h
- **Closed**: 2026-05-17

## Contexto

Para garantir a saúde contínua do cluster de forma pró-ativa e possibilitar a exposição segura e controlada do banco de dados do PostgreSQL, fomos demandados a:
1. **Expor o PostgreSQL externamente através do Ingress Nginx** via protocolo TCP nativo (porta 5432).
2. **Implementar canais de notificação ativa (Webhooks)** no watchdog de saúde do cluster (`cluster_health_check.sh`), de forma que o operador seja notificado instantaneamente no Discord/Slack/Gotify em caso de degradação.

## Desafios de Engenharia de Sistemas Solucionados

### 1. Colisão de Bind no HostNetwork (`Address in use`)
Ao mapear a porta TCP `5432` diretamente no ConfigMap `tcp-services` do Ingress Nginx, o NGINX Controller falhava ao tentar realizar o bind com o seguinte erro em seus logs:
```
[emerg] bind() to 0.0.0.0:5432 failed (98: Address in use)
```
Isso ocorria porque as instâncias da StatefulSet do PostgreSQL já rodam em modo `hostNetwork: true`, ligando-se fisicamente à porta `5432` da interface de rede dos nós do cluster.

**Solução Elegante**:
- Alteramos o ConfigMap `tcp-services` para mapear a porta interna livre `5433` do NGINX para o serviço Postgres (`postgres/postgres-service:5432`).
- No Service LoadBalancer público do Ingress Nginx, expusemos a porta pública `5432` mas a apontamos para o `targetPort: 5433`.
Dessa forma, o tráfego externo bate na porta `5432` do balanceador, é repassado para o listener seguro do Ingress na porta `5433` (livre de colisões), e é encaminhado com sucesso para a porta `5432` do container do banco!

### 2. Watchdog Ativo com Proteção contra Quebra de Shell (`set -u`)
O script `/opt/k8s-ops/cluster_health_check.sh` roda de forma estrita sob `set -uo pipefail`. Qualquer referência a variáveis ou arrays vazios causa abortagem imediata do script.
- Criamos e inicializamos de forma limpa os arrays de controle `CRIT_MESSAGES` e `WARN_MESSAGES` para reter todas as mensagens geradas pelas funções `report_crit` e `report_warn`.
- Escrevemos a função `send_notifications` que lê a variável de ambiente `WATCHDOG_WEBHOOK_URL`. Caso configurada, ela monta um payload markdown completo e o converte para JSON de forma 100% segura usando o utilitário nativo `jq` (prevenindo erros de escape em strings e quebras sob o `set -u`).
- Sincronizamos o script modificado para a produção no nó master `/opt/k8s-ops/cluster_health_check.sh` e garantimos permissões executáveis.

## Testes e Validação em Produção

### 1. Verificação do Ingress Nginx
Validamos que o Ingress Controller recarregou suas configurações sem quaisquer falhas de bind no nó master ou worker:
```
I0517 19:30:10.926667       7 controller.go:228] "Backend successfully reloaded"
```

### 2. Disparo de Webhook Mockado com SSH Reverso
Iniciamos um servidor mock HTTP em python na porta `8098` na nossa máquina local.
- Estabelecemos um túnel SSH reverso: `ssh -R 8098:127.0.0.1:8098 oci-k8s-master -N -f`.
- Disparamos o watchdog no master passando o webhook ativo.
- O watchdog capturou todos os 4 alertas críticos (headroom de CPU acima de 85% nos nós físicos) e 13 warnings de pods e certificados, gerando o payload abaixo recebido e impresso pelo nosso servidor mock:

```json
{
  "content": "### 🏥 **Cluster Health Watchdog Alert!**\n**Cluster**: `oci-k8s-cluster`\n**Status**: 🔴 CRITICAL\nDetected **4 critical issue(s)** and **13 warning(s)**.\n\n**🔴 Critical Issues:**\n- node k8s-master: CPU 746m/800m (93% used, 54m free)\n- node k8s-node-1: CPU 721m/800m (90% used, 79m free)\n- node k8s-node-2: CPU 696m/800m (87% used, 104m free)\n- node k8s-node-3: CPU 721m/800m (90% used, 79m free)\n..."
}
```

Tudo validado com **100% de sucesso sistêmico!**

## Arquivos Modificados

* Local e Remoto: `/opt/k8s-ops/cluster_health_check.sh` e [cluster_health_check.sh](file:///home/dnorio/production-site-antigravity/oci-k8s-cluster/scripts/observability/cluster_health_check.sh)
* [postgres-resources.yaml](file:///home/dnorio/production-site-antigravity/components/postgres/postgres-resources.yaml)
* [deploy.yaml](file:///home/dnorio/production-site-antigravity/components/ingress-nginx/deploy.yaml)
