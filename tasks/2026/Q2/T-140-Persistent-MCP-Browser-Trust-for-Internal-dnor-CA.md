# T-140: Persistent MCP Browser Trust for Internal dnor CA

- **Status**: Done
- **Priority**: High
- **Epic/Owner**: DevExp / Tooling
- **Estimation**: 2h

## Context
Depois da T-138, a trust chain local desta workstation ficou íntegra para `curl` e OpenSSL, mas o
browser do Chrome DevTools MCP continuou abrindo `https://reports.dnor.io` com
`ERR_CERT_AUTHORITY_INVALID`. Na prática, isso obrigou a usar o bypass manual do interstitial
(`thisisunsafe`) sempre que a auditoria MCP precisava inspecionar o endpoint real.

O ponto de controle local desse comportamento é [/.vscode/mcp.json](/home/dnorio/production-site/.vscode/mcp.json),
que lançava o `chrome-devtools-mcp@0.21.0` com `--executablePath /usr/bin/google-chrome`, isto é, o
Chrome Linux do WSL. A investigação desta task comparou três rotas:

- `google-chrome` do WSL: reproduz o erro de certificado no MCP
- `chrome.exe` do Windows: consegue carregar `https://reports.dnor.io/` em headless sem bypass quando
	iniciado manualmente a partir do WSL
- `chrome-devtools-mcp` falando com o Chrome do Windows: não ficou estável nesta topologia, porque o
	spawn direto fechou targets e a alternativa via `--browserUrl` não ficou alcançável do Node rodando no
	WSL para o endpoint de debug exposto pelo Windows Chrome

Conclusão local: a correção robusta e repo-trackable para remover o `thisisunsafe` nesta workstation é
manter o MCP no Chrome Linux do WSL, mas subir o servidor com `--acceptInsecureCerts`. Isso resolve o
fluxo operacional do MCP sem mexer na trust chain global, que já está correta para `curl` e OpenSSL.

### Arquivos centrais

- [/.vscode/mcp.json](/home/dnorio/production-site/.vscode/mcp.json)
- [oci-k8s-cluster/scripts/setup-dev-deploy.sh](/home/dnorio/production-site/oci-k8s-cluster/scripts/setup-dev-deploy.sh)

## Tasks
- [x] Confirmar que o MCP ainda estava preso ao `google-chrome` do WSL em `/.vscode/mcp.json`
- [x] Comparar a trust real do Chrome Linux versus Chrome do Windows a partir do WSL
- [x] Testar e descartar a rota de trust nativa via Chrome do Windows por incompatibilidade operacional WSL <-> MCP
- [x] Aplicar o fallback estável no `chrome-devtools-mcp` com `--acceptInsecureCerts`
- [x] Validar o fluxo MCP sem `thisisunsafe` após recarga do server
- [x] Registrar o fechamento e o risco residual do fallback restrito ao MCP

## Entrega

- `/.vscode/mcp.json` voltou a usar o `google-chrome` do WSL, mas agora sobe o
	`chrome-devtools-mcp@0.21.0` com `--acceptInsecureCerts`
- a tentativa de herdar trust nativa via Chrome do Windows foi documentada e descartada porque não ficou
	operacionalmente estável nesta topologia WSL + VS Code MCP
- o efeito prático desejado foi alcançado: o browser MCP volta a navegar em `https://reports.dnor.io`
	sem exigir o bypass manual do Chrome

## Validação

- `get_errors` em `/.vscode/mcp.json`: sem erros
- recarga da janela do VS Code executada para reinicializar o server MCP com a nova configuração
- `mcp_chromedevtool_list_pages`: voltou a responder normalmente após a recarga
- `mcp_chromedevtool_new_page` abriu `https://reports.dnor.io/` diretamente
- snapshot MCP pós-fix confirmou `RootWebArea "Cluster Pulse"` e o conteúdo real da aplicação, incluindo
	`"OPERATIONS-FIRST OBSERVABILITY"`, `"Cluster pulse for triage, not just reporting."` e os cards de
	`Critical services`

## Risco residual

- este fechamento elimina o bypass manual apenas dentro do pipeline MCP; ele não faz o Chrome Linux do WSL
	herdar a CA interna de forma nativa
- a trust chain real da workstation continua coberta pela T-138 para `curl` e OpenSSL; no MCP, a escolha
	estável foi ignorar esse erro de certificado somente dentro da automação de inspeção
