# T-115 — TUI: App Deploy Menu (Dynamic)

**Status**: 📋 Backlog  
**Priority**: 🔽 Medium  
**Epic**: DevOps  
**Estimate**: 3h  
**Created**: 2026-04-12

---

## Objetivo

Adicionar um menu de deploy de apps na TUI (`k8s_ops_menu.sh`), análogo ao
menu de components (`component_management_menu`), mas dinâmico: descobre os
apps deployáveis automaticamente escaneando o repositório.

---

## Motivação

Após T-114, todo app em `apps/<service>` tem um `deploy.sh` padronizado.
Hoje o deploy requer sair da TUI, navegar até o diretório e executar
`./deploy.sh` manualmente. O objetivo é integrar isso no workflow da TUI
para operabilidade equivalente aos components.

---

## Critérios de Aceite

1. **Descoberta dinâmica**: menu lista apenas os apps que possuem `deploy.sh`
   (glob `../apps/*/deploy.sh` + `../apps/*/publish.sh` a partir de `oci-k8s-cluster/`).
2. **Status em linha**: para cada app exibir o status do pod no cluster em
   tempo real (Running/Pending/CrashLoop/Missing).
3. **Ações disponíveis**:
   - `Deploy / Rebuild` — executa `deploy.sh` (ou `publish.sh`) do app.
   - `Rollout Status` — `kubectl rollout status deployment/...`.
   - `View Logs` — abre logs do pod em `less`.
   - `Restart` — `kubectl rollout restart deployment/...`.
4. **Pré-requisito automático**: antes de qualquer build, verificar se
   `oci-builder` está ativo (`docker buildx inspect oci-builder`); se não,
   oferecer opção de rodar `setup-dev-deploy.sh` automaticamente.
5. **Integração na main_menu**: novo item `🚀 Deploy Apps` entre
   `menu_components` (5) e `menu_dashboard` (6) — deslocar itens subsequentes.

---

## Implementação Sugerida

### Função `app_deploy_menu()` em `k8s_ops_menu.sh`

```bash
app_deploy_menu() {
  while true; do
    # 1. Descobrir apps com deploy.sh
    local apps_dir="$SCRIPT_DIR/../apps"
    local app_list=()
    for script in "$apps_dir"/*/deploy.sh "$apps_dir"/*/publish.sh; do
      [ -f "$script" ] || continue
      local app_name
      app_name=$(basename "$(dirname "$script")")
      app_list+=("$app_name")
    done

    # 2. Para cada app, obter status do pod
    local menu_items="← Back\n"
    for app in "${app_list[@]}"; do
      local label
      label=$(kubectl get deployment -l "app=$app" -A --no-headers 2>/dev/null \
              | awk '{print $2"/"$3" ready"}' | head -1)
      [ -z "$label" ] && label="not deployed"
      menu_items+="$app  [$label]\n"
    done

    # 3. fzf para selecionar app
    local selected
    selected=$(printf "%b" "$menu_items" | "$FZF_BIN" \
      --height=60% --layout=reverse --border \
      --prompt="Deploy App > " \
      --header="Apps (deploy.sh found)") || true
    [ -z "$selected" ] || [[ "$selected" == "← Back" ]] && return

    local chosen_app="${selected%% *}"
    # 4. Submenu de ações para o app selecionado
    _app_action_menu "$chosen_app"
  done
}

_app_action_menu() {
  local app="$1"
  local apps_dir="$SCRIPT_DIR/../apps"
  local deploy_script="$apps_dir/$app/deploy.sh"
  [ -f "$deploy_script" ] || deploy_script="$apps_dir/$app/publish.sh"

  local actions="🚀 Deploy / Rebuild
📋 Rollout Status
📜 View Logs
🔄 Restart Deployment
← Back"

  local selected
  selected=$(echo "$actions" | "$FZF_BIN" \
    --height=40% --layout=reverse --border \
    --prompt="$app > " \
    --header="App: $app") || true
  [ -z "$selected" ] && return

  case "$selected" in
    "🚀 Deploy / Rebuild")
      # Verificar oci-builder
      if ! docker buildx inspect oci-builder &>/dev/null; then
        echo -e "${YELLOW}⚠️  oci-builder não encontrado.${NC}"
        read -p "Executar setup-dev-deploy.sh? [y/N] " yn
        [[ "$yn" =~ ^[Yy]$ ]] && source "$SCRIPT_DIR/scripts/setup-dev-deploy.sh"
      fi
      clear
      pushd "$apps_dir/$app" > /dev/null
      bash deploy.sh 2>/dev/null || bash publish.sh
      popd > /dev/null
      read -p "$(t "press_enter")"
      ;;
    "📋 Rollout Status")
      run_kubectl "rollout status deployment -l app=$app -n default" || true
      read -p "$(t "press_enter")"
      ;;
    "📜 View Logs")
      run_kubectl "logs -l app=$app -n default --tail=200 --follow" 2>/dev/null | less -S
      ;;
    "🔄 Restart Deployment")
      run_kubectl "rollout restart deployment -l app=$app -n default"
      read -p "$(t "press_enter")"
      ;;
  esac
}
```

### Itens de i18n a adicionar (`lib/i18n.sh` ou inline)

```
menu_deploy_apps → "6. 🚀 Deploy Apps"
```

### Ajuste na `main_menu`

- Inserir `$(t "menu_deploy_apps")` após `menu_components` (como item 6).
- Re-numerar itens 6–N (+1).
- Adicionar `case 6) app_deploy_menu ;;` e re-numerar os casos subsequentes.

---

## Arquivos Afetados

| Arquivo                                    | Mudança                                                                  |
| ------------------------------------------ | ------------------------------------------------------------------------ |
| `oci-k8s-cluster/k8s_ops_menu.sh`          | Nova função `app_deploy_menu` + `_app_action_menu` + item na `main_menu` |
| `oci-k8s-cluster/lib/i18n.sh` (se existir) | Nova chave `menu_deploy_apps`                                            |

---

## Dependências

- T-114 ✅ (todos os `deploy.sh` padronizados)
- `setup-dev-deploy.sh` ✅ (criado em T-114)

---

## Notas de Implementação

- Usar `app=<service>` como label selector no `kubectl`; verificar nos
  manifests se o label `app:` corresponde ao nome do diretório.
- O `pushd/popd` é necessário porque `deploy.sh` usa caminhos relativos.
- Não bloquear a TUI se `kubectl` estiver indisponível (sem tunnel):
  mostrar `[kubectl unavailable]` no status e desabilitar ações de rollout.
