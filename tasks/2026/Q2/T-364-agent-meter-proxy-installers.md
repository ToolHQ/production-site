# T-364: agent-meter-proxy — Cross-Platform Installers

- **Status**: In Progress
- **Priority**: 🚨 Critical
- **Owner**: Copilot/VSCode
- **Epic**: agent-meter → SaaS Revenue
- **Branch**: `feat/T-364-agent-meter-proxy-installers`

## Context

O usuário precisa de installers reais que funcionem em Windows, Linux e macOS. O MSI deve:
1. Instalar o certificado CA automaticamente
2. Configurar o proxy como serviço Windows (startup automático)
3. Configurar variáveis de ambiente (HTTPS_PROXY, HTTP_PROXY)

## Solution

### Arquitetura de Installers

| Plataforma | Formato | Ferramenta | Custom Actions |
|------------|---------|------------|----------------|
| Windows x64 | MSI | WiX v5 | CA install, Service, Env vars |
| Windows ARM64 | MSI | WiX v5 | CA install, Service, Env vars |
| Linux x64 | DEB, RPM, TGZ | fpm | CA install, systemd |
| Linux ARM64 | DEB, RPM, TGZ | fpm | CA install, systemd |
| macOS x64 | DMG, PKG | hdiutil + productbuild | CA install, launchd |
| macOS ARM64 | DMG, PKG | hdiutil + productbuild | CA install, launchd |

### WiX MSI Custom Actions

```xml
<!-- 1. Install CA Certificate to Windows Certificate Store -->
<CustomAction Id="InstallCACertificate" 
              Execute="deferred" 
              Impersonate="no"
              PowerShellScript="..." />

<!-- 2. Install as Windows Service -->
<CustomAction Id="InstallWindowsService" 
              Execute="deferred" 
              Impersonate="no"
              PowerShellScript="..." />

<!-- 3. Configure Environment Variables -->
<CustomAction Id="ConfigureEnvironmentVariables" 
              Execute="deferred" 
              Impersonate="no"
              PowerShellScript="..." />
```

### GitHub Actions Workflow

- Build Rust para todas as plataformas (linux-x64, linux-arm64, darwin-x64, darwin-arm64, windows-x64, windows-arm64)
- Package com fpm (DEB/RPM), WiX (MSI), hdiutil (DMG)
- Upload para GitHub Releases

## Files Created/Modified

- `.github/workflows/release-agent-meter-proxy.yml` — Added Windows ARM64 + packaging jobs
- `apps/agent-meter/scripts/release/wix/Product.wxs` — WiX MSI template
- `apps/agent-meter/scripts/release/package-linux.sh` — Linux packaging script
- `apps/agent-meter/scripts/release/package-macos.sh` — macOS packaging script
- `apps/agent-meter/crates/collector/src/routes/setup.rs` — Updated to redirect to GitHub Releases

## Tasks

- [x] Adicionar Windows ARM64 ao build matrix
- [x] Criar WiX MSI template com custom actions
- [x] Criar scripts de packaging Linux (DEB, RPM, TGZ)
- [x] Criar scripts de packaging macOS (DMG)
- [x] Configurar job de packaging no GitHub Actions
- [x] Atualizar setup.rs para redirecionar para GitHub Releases
- [ ] Testar build do proxy no Hetzner builder
- [ ] Criar tag e executar workflow
- [ ] Validar MSI instalando em Windows
- [ ] Validar DEB/RPM instalando em Linux
- [ ] Validar DMG instalando em macOS