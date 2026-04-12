# T-112 — Catalog: Namespace Extraction Fix & Cluster-Only Resolution

**Status**: 📅 Backlog  
**Priority**: 🔽 Medium  
**Epic**: DevExp  
**Estimate**: 2h  
**Created**: 2026-04-12

---

## Problema

Dois issues no `generate_catalog.sh` identificados via relatório HTML:

### 1. Namespace extraction incorreto em `scan_components()`

O `cert-manager` (e possivelmente outros componentes) tem `namespace: "default"` extraído no scan,
porque o parser pega o **primeiro** `namespace:` que aparece nos manifests YAML — que normalmente são
ClusterRoleBindings e ServiceAccounts em `default`, não o namespace real do Deployment.

**Evidência**:
```json
{ "name": "cert-manager", "namespace": "default" }   ← scan_components()
{ "name": "cert-manager", "namespace": "cert-manager" } ← cross_reference() (fallback correto)
```

O cross_reference até funciona por causa do fallback `comp_name → namespace`, mas o campo
`namespace` no JSON fica errado, aparece como `default` na aba Components.

### 2. Cluster-Only: `chain-repair` CronJob em `default`

O único item cluster-only é o CronJob `chain-repair` no namespace `default`.  
Este job é o **chain repair do cert-manager** (imagem `bitnami/kubectl`, rotaciona ACME chains).
Está em `default` porque os manifests originais do cert-manager o deployam ali.

Dois caminhos de resolução:
- **(A) Mover o CronJob para `cert-manager` namespace** no manifest do repo (infra fix)
- **(B) Mapear no catalog**: permitir que componentes declarem `satellite_namespaces` adicionais
  para que o cross_reference os absorva em vez de listá-los como cluster-only

---

## Solução Proposta

### Fix 1 — `scan_components()`: prefer deployment namespace

Ao extrair `namespace` dos manifests, buscar o namespace do **Deployment/StatefulSet/DaemonSet**
em vez do primeiro `namespace:` encontrado:

```bash
# Prioridade: namespace do Deployment > namespace do primeiro workload > "default"
local ns=""
ns=$(grep -r -A2 'kind: Deployment\|kind: StatefulSet\|kind: DaemonSet' "$comp_dir" \
     --include='*.yaml' --include='*.yml' 2>/dev/null \
     | grep 'namespace:' | awk '{print $2}' | head -1)
[[ -z "$ns" ]] && ns=$(grep -r 'namespace:' "$comp_dir" --include='*.yaml' \
     2>/dev/null | awk '{print $2}' | grep -v '^$\|^default$' | sort | uniq -c | sort -rn | awk '{print $2}' | head -1)
[[ -z "$ns" ]] && ns="default"
```

### Fix 2 — Mover `chain-repair` CronJob para `cert-manager` namespace

Editar `components/cert-manager/` para mudar o `namespace:` do CronJob de `default` para
`cert-manager`. Reaplica com `kubectl apply`.

---

## Arquivos Afetados

- `oci-k8s-cluster/scripts/observability/generate_catalog.sh` → `scan_components()`
- `components/cert-manager/` → CronJob manifest (Fix 2)

---

## Critérios de Aceite

- [ ] `cert-manager` aparece com `namespace: cert-manager` na aba Components do HTML  
- [ ] Cluster-Only count = 0 (ou apenas itens legítimos sem owner no repo)  
- [ ] `chain-repair` CronJob está no namespace `cert-manager` no cluster  
- [ ] Nenhum outro componente com namespace incorreto (validar top-5 com `default`)
