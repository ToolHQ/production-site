# Arquitetura de Acesso à Rede — OCI Cluster

> **Última atualização:** 2026-05-26
> **Decisão:** Opção B — DNS público + OCI Security List restrito + Tailscale como overlay

---

## Topologia Final

```
DNS (GoDaddy) — round-robin nos 3 workers:
  *.dnor.io → A 150.136.67.52   (oci-k8s-node-1)
              A 150.136.70.212  (oci-k8s-node-2)
              A 150.136.88.87   (oci-k8s-node-3)

OCI Security List (k8s-public-subnet 10.0.1.0/24):
  TCP 80/443  ← 189.62.149.233/32   (computador fixo do admin)
  TCP 80/443  ← 37.27.85.100/32     (Hetzner CI builder)
  UDP 41641   ← 0.0.0.0/0           (WireGuard Tailscale — mundo todo)
  [... regras SSH pré-existentes ...]

Tailscale subnet routing (cada worker anuncia o próprio IP público):
  oci-k8s-node-1: advertise-routes=150.136.67.52/32
  oci-k8s-node-2: advertise-routes=150.136.70.212/32
  oci-k8s-node-3: advertise-routes=150.136.88.87/32

TLS: Let's Encrypt via DNS-01 (GoDaddy webhook no cert-manager)
     → certs browser-confiáveis, sem precisar abrir porta 80
```

---

## Cenários de Acesso

### Cenário 1 — Celular (3G/4G) com Tailscale ativo ✅

**Pré-requisito:** App Tailscale no S25 com "Accept routes" habilitado.

```
S25 (3G, IP público: 177.x.x.x)
  │ Tailscale ativo + Accept routes
  │
  ├─ DNS: coroot.dnor.io → 150.136.67.52
  │       (resolve normalmente via DNS público)
  │
  ├─ Routing table do Tailscale no S25:
  │  "150.136.67.52/32 é subnet route via oci-k8s-node-1"
  │
  ├─ Pacote externo (o que a OCI VCN vê):
  │  UDP 41641  177.x.x.x → 150.136.67.52    ← WireGuard
  │
  ├─ OCI Security List: UDP 41641 de 0.0.0.0/0 → PERMITIDO ✅
  │  (a Security List NÃO vê TCP 443 — só o WireGuard por fora)
  │
  ├─ WireGuard no node-1 decapsula o pacote →
  │  TCP para 150.136.67.52:443 entra via tailscale0
  │
  ├─ iptables no node-1: tailscale0 → porta 443 → ACCEPT ✅
  │
  └─ nginx (hostNetwork) recebe → HTTPS verde (Let's Encrypt) ✅
```

**Funciona em qualquer rede:** 3G, 4G, Wi-Fi desconhecido, roaming.
O IP do celular nunca precisa ser whitelisted.

---

### Cenário 2 — Computador fixo em casa ✅

**IP:** 189.62.149.233 (whitelisted na Security List)

```
dnorio-base (189.62.149.233)
  │ Tailscale pode estar ligado ou não — irrelevante
  │
  ├─ DNS: coroot.dnor.io → 150.136.70.212 (round-robin → node-2)
  │
  ├─ TCP 443  189.62.149.233 → 150.136.70.212
  │           (conexão direta, sem WireGuard overhead)
  │
  ├─ OCI Security List: 189.62.149.233/32 → TCP 443 → PERMITIDO ✅
  │
  └─ nginx no node-2 → HTTPS verde ✅
```

**Nota:** Round-robin pode jogar para qualquer um dos 3 nós — todos têm o mesmo cert Let's Encrypt wildcard `*.dnor.io`.

---

### Cenário 3a — Computador em viagem (IP desconhecido, sem Tailscale) ❌

```
Hotel/aeroporto (IP: 201.x.x.x)
  │
  ├─ TCP 443  201.x.x.x → 150.136.67.52
  │
  ├─ OCI Security List: 201.x.x.x → NÃO está na whitelist
  │
  └─ BLOQUEADO — connection timeout ❌
```

**Solução rápida:** Adicionar o IP temporário via OCI CLI:

```bash
# Ver IP atual
curl ifconfig.me

# Adicionar à Security List (ver script: scripts/network/update-seclist.sh)
```

---

### Cenário 3b — Computador em viagem COM Tailscale ✅

```
Hotel/aeroporto (IP: 201.x.x.x) + Tailscale instalado + Accept routes
  │
  │ (fluxo idêntico ao Cenário 1 — via WireGuard UDP 41641)
  │
  └─ FUNCIONA em qualquer rede ✅
```

**Recomendação:** Instalar Tailscale no laptop pessoal. Resolve permanentemente o problema de IP variável.

---

### Cenário 4 — Hetzner CI Builder ✅

**IP:** 37.27.85.100 (whitelisted na Security List)

```
Hetzner CAX21 (37.27.85.100)
  │ Sem Tailscale
  │
  ├─ TCP 443  37.27.85.100 → qualquer worker
  │
  ├─ OCI Security List: 37.27.85.100/32 → TCP 443 → PERMITIDO ✅
  │
  └─ Pipelines podem curl para https://reports.dnor.io, etc. ✅
```

---

### Cenário 5 — Internet pública (sem acesso) ❌

```
Qualquer IP público (203.x.x.x)
  │
  ├─ DNS: coroot.dnor.io → 150.136.67.52
  │       (o IP fica visível no DNS público — inevitável com Let's Encrypt)
  │
  ├─ TCP 443  203.x.x.x → 150.136.67.52
  │
  ├─ OCI Security List: IP desconhecido → BLOQUEADO
  │
  └─ Connection timeout — sem mensagem de erro ❌
```

**Nota sobre exposição:** Os IPs dos workers ficam no DNS público, mas a Security List dropa silenciosamente qualquer conexão TCP não autorizada. Scans de porta resultam em timeout. WireGuard em UDP 41641 ignora pacotes com handshake inválido (sem chave privada).

---

## Tabela Resumo

| Quem acessa                            | Meio                | Security List   | Resultado       |
| -------------------------------------- | ------------------- | --------------- | --------------- |
| Celular 3G + Tailscale + Accept routes | WireGuard UDP 41641 | Não vê TCP 443  | ✅ Acesso pleno |
| Computador casa (189.62.149.233)       | TCP direto          | IP na whitelist | ✅ Acesso pleno |
| Computador viagem + Tailscale          | WireGuard UDP 41641 | Não vê TCP 443  | ✅ Acesso pleno |
| Computador viagem sem Tailscale        | TCP direto          | IP desconhecido | ❌ Timeout      |
| Hetzner CI (37.27.85.100)              | TCP direto          | IP na whitelist | ✅ Acesso pleno |
| Internet pública                       | TCP direto          | IP desconhecido | ❌ Timeout      |

---

## Por que DNS-01 e não HTTP-01?

Com HTTP-01, o Let's Encrypt precisa alcançar `http://<dominio>/.well-known/acme-challenge/<token>` pela internet. Isso exigiria abrir porta 80 para `0.0.0.0/0` — quebrando o modelo de whitelist.

Com **DNS-01**, o cert-manager cria um registro TXT `_acme-challenge.<dominio>` via API GoDaddy. O Let's Encrypt valida esse registro via DNS público — sem precisar de acesso HTTP/HTTPS. Porta 80 permanece fechada para a internet.

```
cert-manager → GoDaddy API → TXT _acme-challenge.coroot.dnor.io = "xyz..."
Let's Encrypt → consulta DNS → TXT encontrado → emite cert
cert-manager → remove TXT → armazena cert no K8s Secret
```

---

## Manutenção

### Adicionar novo IP à whitelist

```bash
# Via OCI CLI (ver scripts/network/update-seclist.sh)
NOVO_IP="x.x.x.x/32"
```

### Ver IPs whitelisted atuais

```bash
/home/dnorio/bin/oci network security-list get \
  --security-list-id ocid1.securitylist.oc1.iad.aaaaaaaa5ejiximqihrxqryrnukwl4hfwiysvm2yn5skr7wg5ovtk4ynalua \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
for r in d['data']['ingress-security-rules']:
    tcp = r.get('tcp-options', {})
    dst = tcp.get('destination-port-range', {}) if tcp else {}
    if dst.get('min') in [80, 443]:
        print(r['source'], '→', dst)
"
```

### Verificar estado do Tailscale nos workers

```bash
ssh oci-k8s-master "tailscale status"
```
