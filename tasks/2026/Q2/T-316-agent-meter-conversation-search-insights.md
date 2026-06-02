# T-316: agent-meter — Conversation Search & Insights

## Objetivo
Implementar busca semântica em conversas e gerar insights de padrões de uso para identificar tendências e otimizações.

## Contexto
Com o crescimento do volume de dados coletados, é necessário ferramentas de busca e análise para extrair insights valiosos sobre como os agentes são utilizados.

## Especificações

### 1. Busca Textual
- **Endpoint**: `POST /api/search`
- **Payload**:
```json
{
  "query": "leitura de arquivo",
  "filters": {
    "date_from": "ISO8601",
    "date_to": "ISO8601",
    "model": "gpt-4",
    "client_ip": "192.168.1.1"
  }
}
```
- **Response**: lista de conversations com score de relevância

### 2. Insights Automáticos
- **Top Users**: usuários mais ativos (por client_ip)
- **Top Tools**: ferramentas mais chamadas
- **Top Models**: modelos mais utilizados
- **Error Patterns**: padrões de falhas
- **Cost Trends**: tendências de custo por período

### 3. Dashboard de Insights
- **Gráficos**:
  - Barras: tools mais usadas
  - Linha: custo por dia
  - Pizza: distribuição por modelo
- **Tabela**: conversas com mais erros

### 4. Alertas
- **Threshold**: se custo/dia > X, enviar alerta
- **Pattern**: se erro repetido Y vezes, marcar como padrão

## Implementação

### Backend
1. Adicionar endpoint `/api/search` com full-text search no PostgreSQL
2. Criar views materializadas para insights
3. Jobs periódicos para atualizar estatísticas

### Frontend
1. Página `/insights`
2. Componente `<SearchBar />`
3. Gráficos com Recharts

## Critérios de Aceitação
- [ ] Busca textual retorna resultados relevantes
- [ ] Dashboard de insights carrega sem erros
- [ ] Gráficos são exibidos corretamente
- [ ] Insights são atualizados periodicamente

## Estimativas
- Backend: 2h
- Frontend: 2h
- **Total**: ~4h

## Owner
**Copilot/VSCode**

## Status
- [ ] Backend: Endpoint `/api/search` (não implementado)
- [ ] Backend: Views materializadas para insights (não implementado)
- [ ] Frontend: Página `/insights` (não implementado)

## Notas
- Pode reutilizar queries existentes de reports como base
- Full-text search no PostgreSQL já é suportado