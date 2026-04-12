# T-113 — Catalog: Deploy Actions para Apps Deployable

**Status**: 📅 Backlog  
**Priority**: 🔽 Medium  
**Epic**: DevExp  
**Estimate**: 3h  
**Created**: 2026-04-12

---

## Objetivo

Para cada app com `deploy_readiness: deployable`, o relatório HTML deve mostrar:

1. **Como deployar** — comando exato a executar (caminho do `deploy.sh`, contexto kubectl, etc.)
2. **Botão "Copy command"** — copia o comando pro clipboard com 1 clique (viável em HTML estático)
3. **Link "Open in Terminal"** — gera um `vscode://` deep link que abre o terminal já com o comando (viável no VS Code)

---

## Contexto de Viabilidade

| Feature | Viabilidade | Mecanismo |
|---|---|---|
| Mostrar comando | ✅ Trivial | campo `deploy_script` já no JSON |
| Copy to clipboard | ✅ 100% estático | `navigator.clipboard.writeText()` |
| Open VS Code terminal | ✅ No VS Code | `vscode://vscode.buildfromfile?...` ou `vscode://ms-vscode.remote...` |
| Executar via browser puro | ❌ Impossível | Browsers não têm acesso ao shell |

---

## Implementação

### Fase 1 — `scan_apps()`: enriquecer campo deploy

Em `generate_catalog.sh`, adicionar ao JSON de cada app:

```bash
# Capture first meaningful line of deploy.sh (the actual command)
local deploy_cmd=""
if [[ -n "$deploy_script" ]]; then
    deploy_cmd=$(grep -v '^#\|^$' "$app_dir/$deploy_script" | head -3 | tr '\n' ' ' | xargs)
    deploy_cmd="cd apps/$app_name && bash $deploy_script"
fi
```

Campos adicionados ao JSON:
```json
{
  "deploy_cmd": "cd apps/back-end && bash deploy.sh",
  "deploy_script_path": "apps/back-end/deploy.sh"
}
```

### Fase 2 — HTML: Deploy Action Card no accordion

Quando o usuário clica em um app `deployable`, o accordion de detalhes mostra:

```html
<div class="deploy-action">
  <dt>Deploy Command</dt>
  <dd>
    <code class="cmd-line">cd apps/back-end && bash deploy.sh</code>
    <button onclick="copyCmd(this, 'cd apps/back-end && bash deploy.sh')">📋 Copy</button>
    <a href="vscode://file/home/dnorio/production-site/apps/back-end/deploy.sh">🔗 Open Script</a>
  </dd>
</div>
```

### Fase 3 — Coluna de ação na tabela

Adicionar coluna **"Deploy"** com ícone de ação para apps `deployable`:

```
| App        | ... | Readiness   | Action |
|------------|-----|-------------|--------|
| back-end   | ... | deployable  | [▶ Copy cmd] |
| nginx      | ... | deployable  | [▶ Copy cmd] |
| react-static | . | wip         | —      |
```

### JS: copyCmd helper

```js
function copyCmd(btn, cmd) {
  navigator.clipboard.writeText(cmd).then(() => {
    btn.textContent = '✅ Copied!';
    setTimeout(() => btn.textContent = '📋 Copy', 2000);
  });
}
```

---

## Arquivos Afetados

- `oci-k8s-cluster/scripts/observability/generate_catalog.sh`
  - `scan_apps()`: adicionar `deploy_cmd`, `deploy_script_path`
  - `render_html()`: accordion detalhes + coluna Action

---

## Critérios de Aceite

- [ ] Apps `deployable` mostram comando de deploy no accordion
- [ ] Botão "Copy" copia o comando exato para o clipboard
- [ ] Link "Open Script" abre o arquivo `deploy.sh` no VS Code
- [ ] Apps `wip`/`partial`/`infra-only` mostram `—` na coluna Action
- [ ] Funciona sem backend (HTML estático puro)
