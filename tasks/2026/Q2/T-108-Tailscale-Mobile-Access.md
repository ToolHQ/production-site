# T-108: Acesso Mobile às Ferramentas do Cluster via Tailscale

**Status**: [ ] To Do | **Priority**: 🌟 Feature | **Owner**: Infra | **Est**: 2h

## 🎯 Objetivo

Acessar `coroot.dnor.io`, `nexus.dnor.io`, `k8s.dnor.io` etc. no Chrome do celular, de
qualquer lugar, com segurança — sem expor nada publicamente.

## 🏛️ Arquitetura Alvo

```
📱 Chrome (Android, Tailscale ativo)
  └─ https://coroot.dnor.io  →  resolve para 100.100.107.124 (Tailscale)
        └─ Windows netsh portproxy :443 → WSL2 :8443
              └─ SSH tunnel (WSL2) :8443 → oci-k8s-master :443
                    └─ nginx → ingress-nginx → Coroot / Nexus / etc
```

Tudo trafega pela VPN mesh do Tailscale. IP `100.100.107.124` não é roteável na internet —
só dispositivos no seu Tailnet conseguem alcançar.

## 📦 Dependências / Estado Atual

| Item | Estado |
|---|---|
| Tailscale no PC (dnorio-base) | ✅ ativo — IP `100.100.107.124` |
| Tailscale no celular | ✅ ativo |
| SSH tunnel kubectl (6445→6443) | ✅ ativo via TUI |
| SSH tunnel HTTPS (8443→443) | ❌ falta |
| `netsh portproxy` no Windows | ❌ falta |
| CoreDNS (WSL2, responde `*.dnor.io`) | ❌ falta |
| Tailscale split DNS → CoreDNS | ❌ falta |
| CA cert instalada no Android | ❌ falta |

## 📋 Fases

### Fase 1: SSH Tunnel HTTPS

Adicionar a porta 443 ao tunnel existente. Opção a definir:

**Opção A — manual ad-hoc** (mais simples, sem persistência):
```bash
ssh -L 6445:localhost:6443 -L 8443:localhost:443 oci-k8s-master
```

**Opção B — via TUI** (recomendado): adicionar opção no Connect Menu para iniciar
o tunnel com `-L 8443:localhost:443` junto do tunnel kubectl. O tunnel já existe
em algum submenu do TUI — basta adicionar o bind extra.

- [ ] Identificar onde o tunnel kubectl é iniciado no `k8s_ops_menu.sh`
- [ ] Adicionar `-L 8443:localhost:443` no mesmo comando SSH do tunnel
- [ ] Testar: `curl -k https://localhost:8443 -H "Host: coroot.dnor.io"` → deve retornar 200/302

### Fase 2: netsh portproxy (Windows)

O celular conecta no IP Tailscale do Windows. WSL2 tem IP interno diferente (`172.x.x.x`).
Precisa de um portproxy no Windows:

```powershell
# Rodar no PowerShell como Admin
$wsl = (wsl hostname -I).Trim().Split()[0]
netsh interface portproxy add v4tov4 `
    listenaddress=100.100.107.124 `
    listenport=443 `
    connectaddress=$wsl `
    connectport=8443
```

- [ ] Criar script `tools/setup-mobile-access.ps1` com o comando acima + verificação
- [ ] Testar do celular: `curl -k https://100.100.107.124 -H "Host: coroot.dnor.io"`
- [ ] Verificar se o Windows Firewall bloqueia a porta 443 no perfil "Público/Privado"
      (Tailscale usa perfil de rede privado — normalmente OK, mas confirmar)

> ⚠️ O portproxy some ao reiniciar. Avaliar se vale adicionar ao Task Scheduler ou
> se o TUI pode emitir o comando via `cmd.exe` quando iniciar o tunnel.

### Fase 3: DNS — CoreDNS no WSL2

O celular precisa resolver `*.dnor.io` para `100.100.107.124` (não para a IP pública da OCI).

**Solução**: CoreDNS rodando no WSL2, ouvindo no `100.100.107.124:53` (via portproxy ou bind
direto), com uma zone simples:

```
# Corefile
dnor.io:53 {
    template IN A dnor.io {
        answer "{{ .Name }} 60 IN A 100.100.107.124"
    }
    log
}

.:53 {
    forward . 1.1.1.1
    log
}
```

O Tailscale **split DNS** aponta `dnor.io` → `100.100.107.124:53` — só os dispositivos no
Tailnet recebem essa resolução. Para o resto da internet, `*.dnor.io` continua sem DNS público
(behavior atual).

- [ ] Instalar CoreDNS no WSL2 (binário único, sem Docker):
      `curl -sL https://github.com/coredns/coredns/releases/latest/download/coredns_*_linux_arm64.tgz | tar xz`
      (ou `_amd64` dependendo da arquitetura do WSL2)
- [ ] Criar `tools/coredns/Corefile` e `tools/coredns/dnor.io.db`
- [ ] Iniciar CoreDNS como systemd unit no WSL2 (`tools/coredns/coredns.service`)
- [ ] Configurar portproxy UDP 53 (netsh suporta UDP via `protocol=udp`):
      ```powershell
      netsh interface portproxy add v4toudpv4 `
          listenaddress=100.100.107.124 listenport=53 `
          connectaddress=$wsl connectport=5353
      ```
      > Nota: `netsh portproxy` só suporta TCP nativamente. Para UDP/53, alternativa mais
      > robusta é rodar o CoreDNS diretamente ouvindo no IP Tailscale do Windows usando
      > WSL2 mirrored networking (Windows 11) ou via `socat` para bridge UDP.
- [ ] Testar resolução do celular: `dig coroot.dnor.io @100.100.107.124`
- [ ] Configurar Tailscale split DNS: admin.tailscale.com → DNS → Nameservers → Add
      custom nameserver: `100.100.107.124` para domínio `dnor.io`

> 💡 Se WSL2 estiver no modo **mirrored networking** (Windows 11 22H2+), o CoreDNS pode
> ouvir diretamente no IP Tailscale sem portproxy UDP. Verificar: `%USERPROFILE%\.wslconfig`
> se tem `networkingMode=mirrored`.

### Fase 4: CA Cert no Android

Para o Chrome não exibir aviso de certificado:

- [ ] Exportar CA via TUI Security Menu → opção 5 → salvar `dnor-ca-issuer.crt`
- [ ] Transferir para o celular (AirDrop / Telegram para si mesmo / Google Drive)
- [ ] Android: **Configurações → Segurança → Mais configurações de segurança →
      Criptografia e credenciais → Instalar um certificado → Certificado CA**
- [ ] Verificar no Chrome: abrir `https://coroot.dnor.io` — cadeado verde sem aviso

> ⚠️ No Android, certificados CA instalados pelo usuário são confiáveis pelo sistema mas o
> Chrome pode exibir aviso suplementar. Para suprimir completamente é necessário instalar
> como "system CA" (requer root) ou usar o perfil MDM. Na prática o aviso é apenas
> informativo e o acesso funciona normalmente.

## ✅ Definition of Done

- [ ] `curl https://coroot.dnor.io` no celular (com Tailscale ativo) abre a interface
- [ ] Sem alerta de certificado no Chrome (ou alerta apenas cosmético do Android CA)
- [ ] Desligar Tailscale no celular → URL para de funcionar (confirma que não é público)
- [ ] Script `tools/setup-mobile-access.ps1` documentado e funcional
- [ ] CoreDNS configurado em `tools/coredns/`

## 🔗 Contexto

- Tailscale IP do PC: `100.100.107.124` (dnorio-base)
- SSH host: `oci-k8s-master`
- nginx listening `:443` no master (confirmado)
- Ingress-nginx em NodePort 32335 (HTTPS) — nginx do host faz proxy
- CA atual: `dnor-root-ca`, expira 2026-06-23, exportável via TUI opção 5
- T-107 já resolveu CA duration + chain integrity
