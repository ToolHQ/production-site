# T-118 — TUI: Gerenciador de js-libs (@dnorio/\*)

**Status**: ✅ Done  
**Priority**: 🔼 High  
**Epic**: DevOps / TUI  
**Estimate**: 2h  
**Created**: 2026-04-13  
**Depends on**: T-116 (npm-group no Nexus), T-117 (primeira publicação)  
**Blocks**: —

---

## Contexto

Após T-116 + T-117 garantirem que o pipeline npm está funcional, a T-118 adiciona
um submenu dedicado na TUI (`k8s_ops_menu.sh`) para gerenciar o ciclo de vida das
libs `@dnorio/*` do monorepo Lerna em `~/js-libs`.

O objetivo é que o Lead DevOps consiga, sem sair da TUI:

- Ver o estado atual das libs (versão local vs. versão no Nexus)
- Publicar versões novas via Lerna
- Verificar se o Nexus está saudável para receber publicações

---

## Critérios de Aceite

1. Novo item **"js-libs Manager"** aparece no menu principal da TUI
2. Submenu exibe, para cada `@dnorio/*`, a versão local e a versão no `npm-repo`
3. Opção "Publish All" executa `lerna publish from-package --yes` sem sair da TUI
4. Opção "Build All" executa `lerna run tsc` (build TypeScript)
5. Opção "Check Registry" verifica se `npm-group`, `npm-repo`, e `npm-proxy` estão OK no Nexus
6. Pré-condição: script detecta se `~/js-libs` existe; se não, avisa e retorna

## Tasks

- [x] Validar a estrutura real de `~/js-libs`, incluindo `lerna.json`, pacotes `@dnorio/*` e `.npmrc`
- [x] Adicionar o item `js-libs Manager` ao menu principal da TUI sem quebrar a numeração existente
- [x] Implementar submenu dedicado com ações de status, build, publish, health check e visualização do `.npmrc`
- [x] Integrar consulta real ao Nexus para comparar versão local vs versão publicada no `npm-repo`
- [x] Persistir logs das ações de build/publish no host, no mesmo padrão operacional da TUI
- [x] Validar o fluxo contra o monorepo real `~/js-libs` e a API do Nexus em `localhost:8081`

---

## Implementação

### Menu Principal — novo item

No `k8s_ops_menu.sh`, adicionar na `main_menu()`:

```bash
"📦 js-libs Manager" "jslibs_menu"
```

Reordenar itens se necessário (após item de App Deploy ou antes de Manutenção).

### Função `jslibs_menu()`

```bash
jslibs_menu() {
    local JS_LIBS_DIR="$HOME/js-libs"

    if [[ ! -d "$JS_LIBS_DIR" ]]; then
        dialog_msgbox "Erro" "Diretório ~/js-libs não encontrado.\nClone o repositório primeiro."
        return 1
    fi

    while true; do
        local choice
        choice=$(whiptail --title "📦 js-libs Manager" --menu "Selecione uma operação:" 18 60 8 \
            "1" "📊 Status: versão local vs. Nexus" \
            "2" "🔨 Build All (lerna run tsc)" \
            "3" "🚀 Publish All (lerna publish from-package)" \
            "4" "🔍 Check Nexus NPM Health" \
            "5" "📝 Ver .npmrc atual" \
            "B" "← Voltar" \
            3>&1 1>&2 2>&3)

        case "$choice" in
            1) jslibs_status ;;
            2) jslibs_build_all ;;
            3) jslibs_publish_all ;;
            4) jslibs_check_nexus ;;
            5) jslibs_show_npmrc ;;
            B|"") return 0 ;;
        esac
    done
}
```

### Função `jslibs_status()` — versão local vs. Nexus

```bash
jslibs_status() {
    local JS_LIBS_DIR="$HOME/js-libs"
    local NEXUS="http://localhost:8081"
    local AUTH
    AUTH=$(credstore_get_credential "nexus-admin" | jq -r '"admin:" + .password')

    # Versão local do lerna.json
    local local_version
    local_version=$(jq -r '.version' "$JS_LIBS_DIR/lerna.json")

    # Listar pacotes e checar no Nexus
    local report=""
    for pkg_json in "$JS_LIBS_DIR"/packages/*/package.json; do
        local pkg_name
        pkg_name=$(jq -r '.name' "$pkg_json")
        # Buscar versão mais recente no Nexus
        local nexus_version
        nexus_version=$(curl -s -u "$AUTH" \
            "$NEXUS/service/rest/v1/search?repository=npm-repo&format=npm&name=$pkg_name" \
            | jq -r '.items[0].version // "not found"' 2>/dev/null || echo "error")
        report+="$pkg_name | local: $local_version | nexus: $nexus_version\n"
    done

    echo -e "$report" | column -t -s '|' | dialog_msgbox_scroll "Status @dnorio/*"
}
```

### Função `jslibs_publish_all()`

```bash
jslibs_publish_all() {
    local JS_LIBS_DIR="$HOME/js-libs"

    # Pré-condição: .npmrc deve ter token de publish
    if ! grep -q "_authToken" "$JS_LIBS_DIR/.npmrc" 2>/dev/null; then
        dialog_msgbox "Erro" "Não há _authToken no ~/js-libs/.npmrc\nExecute T-117 para configurar."
        return 1
    fi

    run_in_pane "cd $JS_LIBS_DIR && lerna publish from-package --yes 2>&1 | tee /tmp/lerna-publish.log"
}
```

### Função `jslibs_check_nexus()`

Verifica se os 3 repos npm estão presentes via API Nexus:

```bash
jslibs_check_nexus() {
    local NEXUS="http://localhost:8081"
    local AUTH
    AUTH=$(credstore_get_credential "nexus-admin" | jq -r '"admin:" + .password')

    local repos_json
    repos_json=$(curl -s -u "$AUTH" "$NEXUS/service/rest/v1/repositories" 2>/dev/null)

    local npm_repos
    npm_repos=$(echo "$repos_json" | jq -r '[.[] | select(.format=="npm") | .name + " (" + .type + ")"] | join("\n")')

    if echo "$npm_repos" | grep -q "npm-group"; then
        dialog_msgbox "✅ Nexus NPM OK" "Repositórios npm encontrados:\n\n$npm_repos"
    else
        dialog_msgbox "⚠️ Nexus NPM Incompleto" "Repositórios npm:\n\n$npm_repos\n\nnpm-group não encontrado — execute T-116."
    fi
}
```

---

## Arquivos Afetados

| Arquivo                           | Mudança                                                        |
| --------------------------------- | -------------------------------------------------------------- |
| `oci-k8s-cluster/k8s_ops_menu.sh` | nova função `jslibs_menu()` + submenus + item no `main_menu()` |
| `oci-k8s-cluster/lib/i18n.sh`     | string `menu_jslibs`                                           |
| `oci-k8s-cluster/testing/k8s_ops_menu.bats` | cobertura para helpers de auth/status/git worktree do fluxo js-libs |

---

## Notas

- O `~/js-libs` está fora do repositório `production-site` — o script acessa via `$HOME/js-libs`.
- Confirmar se `whiptail` está disponível em todos os nós (ou usar `fzf` como nas outras partes da TUI).
- O `run_in_pane` / `dialog_msgbox_scroll` — verificar utilitários existentes na TUI e adaptar ao padrão já usado.
- T-118 não conflita com T-117: T-117 é pré-condição (primeiro publish manual), T-118 automatiza o fluxo contínuo.
- Implementação final ficou em `fzf`, não `whiptail`, para reaproveitar o padrão já dominante no `k8s_ops_menu.sh` e evitar dependência extra.
- O lookup de versões no Nexus precisou consultar a Search API pelo basename do pacote (`logger`, `models-core`, etc.), porque o índice retornado pelo Nexus para npm não preserva o scope `@dnorio/` no campo `name`.
- O fluxo de publish ganhou um preflight de worktree limpo porque o `lerna publish from-package --yes` falha com `EUNCOMMIT` quando o monorepo está sujo; a TUI agora explica isso antes da chamada ao Lerna.

## Validação Final — 2026-04-19

- `~/js-libs` foi detectado corretamente, com 8 pacotes `@dnorio/*`, `lerna.json` em `0.0.175` e `.npmrc` apontando para `https://nexus.dnor.io/repository/npm-group`.
- O status local-vs-Nexus foi validado ao vivo via helpers novos: os 8 pacotes retornaram `0.0.175` local e `0.0.175` no `npm-repo` do Nexus.
- O health check do registry confirmou `npm-group`, `npm-repo` e `npm-proxy` presentes e saudáveis via API do Nexus em `http://localhost:8081`.
- A ação **Build All** executou com sucesso o comando `npx lerna run tsc`, compilando os 8 pacotes e persistindo log em `logs/tui-jslibs/20260419_223128_js-libs_build-all.log`.
- A tentativa de publish bruto expôs a pré-condição real do Lerna (`EUNCOMMIT` com worktree sujo); por isso o fluxo final da TUI passou a bloquear cedo com mensagem clara listando os arquivos pendentes antes de chamar `lerna publish from-package --yes`.
- O log bruto que capturou esse comportamento ficou em `logs/tui-jslibs/20260419_223220_js-libs_publish-all.log`, e o guardrail final foi revalidado diretamente pela função `jslibs_publish_all`.
