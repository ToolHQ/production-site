# T-119 — TUI: App Deploy Execution Logs

**Status**: ✅ Done  
**Priority**: 🔼 High  
**Epic**: DevOps  
**Estimate**: 2h  
**Created**: 2026-04-13

---

## Objetivo

Melhorar a execucao de `Deploy / Rebuild` na TUI (`oci-k8s-cluster/k8s_ops_menu.sh`)
para que o comando do app seja:

1. **streamado ao vivo** na tela durante a execucao
2. **persistido em arquivo no host** para analise posterior
3. **facilmente localizavel** apos falha ou sucesso

---

## Contexto

O fluxo atual do menu de apps executa `bash deploy.sh` ou `bash publish.sh`
diretamente dentro do diretório do app. Em caso de falha, a TUI apenas mostra
`Deploy failed — check output above`, sem salvar stdout/stderr em um arquivo
local de execucao.

Na pratica, isso impede investigacao posterior quando o terminal foi fechado,
quando o erro rolou rapido demais, ou quando precisamos comparar tentativas
sucessivas de deploy. O caso concreto foi o `apps/nginx/publish.sh`, cujo erro
nao ficou persistido no host e portanto nao pôde ser inspecionado depois.

O comportamento desejado e um padrao semelhante a:

- criar um diretório local no host, por exemplo `logs/tui-app-deploy/`
- gerar um arquivo por execucao (`timestamp + app + acao`)
- usar `tee` ou mecanismo equivalente para manter streaming e persistencia
- imprimir ao final o caminho do log gerado para consulta imediata

---

## Escopo Tecnico

### Fluxo alvo

No submenu `_app_action_menu()`:

1. Antes de executar o script, criar diretório de logs local no host
2. Montar nome de arquivo deterministico para a execucao
3. Rodar `deploy.sh`/`publish.sh` com redirecionamento de `stdout` e `stderr`
   para streaming na tela e persistencia no arquivo
4. Em caso de falha, mostrar mensagem clara com o caminho do arquivo salvo
5. Em caso de sucesso, igualmente mostrar onde o log ficou salvo

### Requisitos funcionais

- o usuario deve continuar vendo o progresso ao vivo
- o log deve conter `stdout` + `stderr`
- o caminho salvo deve existir no host local, fora de `/tmp`
- a TUI nao deve esconder o exit code do script
- o log precisa identificar qual app e qual script foram executados

### Arquivos candidatos

- `oci-k8s-cluster/k8s_ops_menu.sh`
- `apps/*/deploy.sh`
- `apps/*/publish.sh`
- `logs/` (novo subdiretorio de runtime da TUI, se adotado)

---

## Tasks

- [x] Confirmar o melhor diretório de persistencia no host para logs de execucao da TUI
- [x] Mapear o ponto exato em `_app_action_menu()` onde `deploy.sh`/`publish.sh` e invocado
- [x] Implementar helper para gerar nome de arquivo com timestamp, app e acao
- [x] Implementar streaming + persistencia de `stdout`/`stderr` usando `tee` ou equivalente seguro
- [x] Preservar e reportar corretamente o exit code real do script executado
- [x] Exibir ao final da execucao o caminho completo do log salvo no host
- [x] Garantir que falhas de pre-requisito (`docker`, `oci-builder`, `kubectl`, `KUBECONFIG`) tambem aparecam no arquivo persistido
- [x] Validar o fluxo com uma nova tentativa de deploy do `apps/nginx`
- [x] Confirmar que, apos a tentativa, o log pode ser lido diretamente deste workspace

---

## Critérios de Aceite

- [x] `Deploy / Rebuild` continua exibindo output ao vivo na TUI
- [x] Toda execucao gera arquivo local persistente no host
- [x] O arquivo inclui `stdout` e `stderr`
- [x] A TUI mostra o caminho final do log salvo
- [x] Em falha de deploy, e possivel inspecionar o erro depois sem repetir o comando
- [x] O proximo teste com `apps/nginx` produz um log acessivel para diagnostico

---

## Resultado

Implementado em `oci-k8s-cluster/k8s_ops_menu.sh`:

- diretório de logs local no host em `logs/tui-app-deploy/`
- arquivo por execução com timestamp + app + script
- streaming ao vivo e persistência de `stdout`/`stderr`
- captura explícita de falhas de pré-requisito antes do deploy
- mensagem final com o caminho do log salvo

Também foi adicionada cobertura em `oci-k8s-cluster/testing/k8s_ops_menu.bats`
para validar geração do path e persistência do output com exit code.

Validação real concluída com `apps/nginx`: a execução gerou o arquivo
`/home/ToolHQ/production-site/logs/tui-app-deploy/20260413_160142_nginx_publish.log`,
confirmando persistência local no host e leitura posterior a partir deste workspace.
O erro capturado no log foi de build da imagem: `geoipupdate@v7.1.1` agora exige
Go `>= 1.23.0`, mas o Dockerfile ainda usa `golang:1.22.3-alpine3.19`.
