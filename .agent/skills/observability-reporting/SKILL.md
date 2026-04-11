---
name: observability-reporting
description: Geração e análise do relatório de inventário do cluster.
---

# Inventory Report

O script `scripts/observability/generate_inventory_report.sh` gera uma página HTML estática com o estado de saúde de todo o cluster.

## Como Gerar

Via TUI: _Generate Inventory Report_
Manual:

```bash
cd oci-k8s-cluster
./scripts/observability/generate_inventory_report.sh
```

## Interpretação (Semáforo)

- 🟢 **Normal/Floor**: Uso seguro ou carga baixa (CPU≤50m, RAM≤64Mi).
- 📉 **Waste**: Recurso alocado excessivamente (>95% ocioso). **Ação**: Reduzir Request.
- ⚠️ **Risk**: Uso próximo do limite (>90%). **Ação**: Aumentar Limit.
- 🔴 **No Limit**: Crítico. Pod sem limites configurados. **Ação**: Adicionar Resources no YAML.
