# T-120 — Nginx Image: Build Toolchain Refresh

**Status**: 🏎️ In Progress  
**Priority**: 🚨 Critical  
**Epic**: DevOps  
**Estimate**: 2h  
**Created**: 2026-04-13  
**Depends on**: T-119 (logs de execucao persistidos)  
**Blocks**: novo deploy do app `nginx`

---

## Contexto

O novo fluxo de logs da TUI (T-119) permitiu capturar com precisão a causa da falha
do `apps/nginx/publish.sh`: o build da imagem quebra logo no início do Dockerfile,
antes do deploy prosseguir.

Falha registrada em
`/home/dnorio/production-site/logs/tui-app-deploy/20260413_160142_nginx_publish.log`:

```text
go install github.com/maxmind/geoipupdate/v7/cmd/geoipupdate@latest
github.com/maxmind/geoipupdate/v7@v7.1.1 requires go >= 1.23.0
```

O `apps/nginx/Dockerfile` ainda usa `golang:1.22.3-alpine3.19` no stage `base`,
então a dependência `@latest` deixou de ser compatível com a imagem atual.

Esta task existe para atualizar a base da imagem nginx de forma segura e mínima,
restabelecendo a capacidade de rodar `publish.sh` novamente sem regressão nos
módulos extras (`geoip2`, `headers-more`) nem no target ARM64 do cluster OCI.

---

## Critérios de Aceite

1. `apps/nginx/Dockerfile` deixa de falhar na instalação do `geoipupdate`
2. A estratégia escolhida fica explícita e reproduzível: subir Go base ou pinar versão compatível
3. `apps/nginx/publish.sh` volta a executar build completo sem erro de toolchain Go
4. O log persistido da nova execução confirma ausência do erro `requires go >= 1.23.0`
5. A mudança preserva compatibilidade com ARM64 e com o builder `oci-builder`

---

## Tasks

- [x] Confirmar no Dockerfile e no log qual stage quebra e qual dependência introduziu o requisito de Go `>= 1.23`
- [x] Definir a correção mais estável para este cluster: atualizar imagem base Go ou pinar `geoipupdate` em versão compatível
- [x] Ajustar `apps/nginx/Dockerfile` com a menor mudança segura e documentar a razão no task file
- [ ] Rodar novo `publish.sh` do `apps/nginx` via fluxo atual da TUI ou comando equivalente do app
- [ ] Validar no log persistido que o erro de toolchain sumiu e registrar o caminho do artefato gerado
- [ ] Atualizar status da task e o KANBAN após o rerun

---

## Arquivos Afetados

| Arquivo | Mudança esperada |
| --- | --- |
| `apps/nginx/Dockerfile` | atualizar toolchain Go ou pin da dependência `geoipupdate` |
| `apps/nginx/publish.sh` | revisar apenas se necessário para compatibilidade/diagnóstico |
| `tasks/2026/Q2/T-120-Nginx-Image-Build-Toolchain-Refresh.md` | registrar decisão técnica e validação |

---

## Notas

- Priorizar a solução mais previsível para ambiente ARM64 e com pouco recurso.
- Evitar upgrades amplos de Alpine/NGINX se o problema puder ser resolvido só no stage Go.
- O log de T-119 virou a evidência base para esta correção; não repetir investigação sem consultar esse artefato.
- Decisão adotada: pin em `geoipupdate v7.1.0`, que ainda declara `go 1.21` com `toolchain go1.22.3`; evita upgrade maior da base `golang:1.22.3-alpine3.19`.
- Tentativas de rerun nesta sessão geraram `logs/tui-app-deploy/20260413_161339_nginx_publish_t120.log` e `logs/tui-app-deploy/20260413_161418_nginx_publish_t120.log`, mas ambas ficaram bloqueadas pelo ambiente local do agente (`bash` do snap sem permissão de execução e ausência de `docker` no `PATH`).
