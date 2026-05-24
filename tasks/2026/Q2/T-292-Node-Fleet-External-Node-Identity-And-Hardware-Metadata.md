# T-292: Node Fleet — Correção de identidade de nós externos + colunas IP/Arquitetura/SO

- **Status**: Done
- **Priority**: 🔼 High
- **Owner**: Copilot/VSCode
- **Epic**: Cluster Pulse / Observability
- **Est**: 5h

## Contexto

O painel Node Fleet está misturando metadados de nós externos com o cluster OCI-K8S e usando hostname hardcoded para SSD Nodes (`ssdnodes-monstro`). Isso gera confusão operacional (cluster incorreto, nome divergente da máquina real) e reduz a capacidade de diagnóstico rápido.

Também faltam colunas essenciais para operação:

- IP da máquina
- Arquitetura (ex.: arm64, x86_64)
- Sistema operacional (ex.: Linux + kernel)

## Escopo Técnico

### Backend (Rust API)

- [ ] Atualizar o mapeamento em `apps/rs-observability-api/src/main.rs` para não depender de hostname fixo para IPs externos
- [ ] Introduzir metadados de host no payload de nós (ex.: `ip`, `architecture`, `os`, `provider`)
- [ ] Corrigir classificação de cluster/provedor para nós externos (ex.: SSD Nodes não deve aparecer como OCI-K8S)
- [ ] Buscar nome real da máquina por série Prometheus (`node_uname_info` / labels compatíveis) com fallback seguro
- [ ] Garantir consistência da chave usada em `node_metrics` e `node_history` (evitar quebra entre nome exibido e chave de métrica)

### Frontend (Preact)

- [ ] Atualizar tipos em `apps/rs-observability-api/web-v2/src/types/api.ts` com os novos campos
- [ ] Adicionar colunas no `apps/rs-observability-api/web-v2/src/components/NodesPanel.tsx` para IP, Arquitetura e Sistema Operacional
- [ ] Ajustar busca/filtro para considerar hostname, IP, arquitetura e SO
- [ ] Manter legibilidade mobile (colunas extras com estratégia responsiva para não quebrar layout)

### Exportações

- [ ] Incluir os novos campos no export em `apps/rs-observability-api/web-v2/src/utils/export.ts` (JSON e CSV)

## Critérios de Aceite

- [ ] SSD Nodes aparece com provider/cluster correto e sem hostname hardcoded incorreto
- [ ] Tabela Node Fleet exibe IP, Arquitetura e SO para cada host com dados disponíveis
- [ ] Hetzner, OCI e SSD Nodes permanecem distinguíveis visualmente
- [ ] Export CSV/JSON preserva os novos campos de inventário
- [ ] Sem regressão nos alertas de CPU/Mem/Disk já existentes

## Observações de Implementação

- Priorizar origem de verdade em labels Prometheus sempre que possível.
- Quando um campo não estiver disponível, exibir fallback explícito (ex.: `unknown`) em vez de mascarar dado.
- Evitar strings mágicas de host no código de produção; centralizar mapeamento estático apenas como fallback temporário.

## Evidência de Validação Ao Vivo (2026-05-24)

- Deploy executado via `apps/rs-observability-api/deploy.sh` com setup oficial (`setup-dev-deploy.sh`)
- Rollout validado: `kubectl rollout status deploy/rs-observability-api-deployment -n default`
- Imagem ativa: `registry.local:31444/repository/docker-repo/rs-observability-api:1779647139`
- Endpoint validado: `https://reports.dnor.io/api/live/overview`
- Resultado do payload:
	- `required_fields_all_nodes=True` para `ip`, `architecture`, `operating_system`
	- Nó SSD: `ssdnodes-6a12f10c9ef11` com `cluster=SSD-NODES`, `ip=104.225.218.78`, `arch=x86_64`
	- Nó Hetzner: `ubuntu-8gb-hel1-3` com `cluster=HETZNER`, `ip=37.27.85.100`, `arch=aarch64`
