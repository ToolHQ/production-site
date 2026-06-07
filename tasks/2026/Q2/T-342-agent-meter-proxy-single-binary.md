# T-342: agent-meter-proxy — Single Binary HTTPS Proxy

- **Status**: In Progress
- **Priority**: 🚨 Critical
- **Owner**: Copilot/VSCode
- **Epic**: agent-meter → SaaS Revenue
- **Branch**: `feat/T-342-agent-meter-proxy`

## Context

Os scripts shell atuais (`cursor-proxy/`, `eclipse-proxy/`) são antiprofissionais para um produto open-source:

- Dependem de `bash` (não funciona em PowerShell nativo, Git Bash limitado)
- Exigem `mitmproxy` + `python3` + `httpx` instalados manualmente
- Dois interceptors Python separados com lógica duplicada (~80% overlap)
- `copilot-cli-metered.sh` é um wrapper bash no diretório do Eclipse para monitorar o Copilot CLI
- Nenhum versionamento (sem tags, sem releases, sem changelogs)

**Solução**: Um único binário Rust (`agent-meter-proxy`) que:

1. Embute toda a lógica de MITM proxy (substitui mitmproxy + Python)
2. Gera e instala CA certificates automaticamente
3. Detecta IDE por user-agent (unificando cursor_interceptor + copilot_interceptor)
4. Funciona em Linux, macOS, Windows (cross-compile via GitHub Actions)
5. Instalável via `curl -fsSL | sh` (ou `Invoke-WebRequest` no PowerShell)
6. Versionado com tags semânticas + GitHub Releases

### Arquitetura

```
agent-meter-proxy
├── subcommand: setup     → gera CA, instala no sistema, configura IDE
├── subcommand: start     → inicia HTTPS proxy em :8898 (foreground ou daemon)
├── subcommand: status    → status do proxy + últimas 10 linhas de log
├── subcommand: stop      → para o daemon
├── subcommand: wrap      → lança IDE/CLI com HTTPS_PROXY já configurado
│                           ex: agent-meter-proxy wrap cursor .
│                           ex: agent-meter-proxy wrap gh copilot suggest "..."
│                           ex: agent-meter-proxy wrap claude "explain this"
└── subcommand: install   → auto-instala em ~/.local/bin ou %USERPROFILE%\.local\bin
```

### Crate: `hudsucker`

Rust MITM proxy library (baseada em `hyper` + `tokio` + `rcgen`):
- Gera CA certs com `rcgen`
- Intercepta HTTPS com on-the-fly certificate generation
- Handlers `request_handler` / `response_handler` para captura
- Production-ready, usado em projetos como `rathole`

## Tasks

- [ ] Criar crate `crates/proxy/` no workspace
- [ ] Implementar MITM proxy com `hudsucker` (hosts: Anthropic, OpenAI, Copilot, Cursor.sh)
- [ ] Unificar lógica de interceptação (extrair model, tokens, tool_calls, session)
- [ ] Construir OTLP span e enviar ao collector
- [ ] Subcommand `setup` — gerar CA com `rcgen`, instalar no sistema
- [ ] Subcommand `start` — iniciar proxy (foreground + daemon mode)
- [ ] Subcommand `wrap` — lançar IDE/CLI com env vars corretas
- [ ] Subcommand `status/stop` — operações do daemon
- [ ] Cross-compile CI (GitHub Actions: linux-x86_64, linux-arm64, darwin-arm64, windows-x86_64)
- [ ] Install script (`install.sh` + `install.ps1`)
- [ ] Atualizar docs.html, README, capture-setup.md
- [ ] Deprecar `cursor-proxy/` e `eclipse-proxy/`
- [ ] Build → Deploy → Browser MCP validation → PR → Merge
