# T-151: Ingress Edge Decoupling from Master

- **Status**: Done
- **Priority**: High
- **Epic/Owner**: Infra
- **Estimation**: 4h

## Context
Durante a execucao da [T-150](T-150-Master-Rootfs-Dependency-Reduction.md), a borda do cluster foi
validada como dependente do `k8s-master` de forma direta:

- o `ingress-nginx-controller` continua com `hostNetwork: true`, `replicas: 1` e
  `nodeSelector: k8s-master` em [components/ingress-nginx/deploy.yaml](../../../components/ingress-nginx/deploy.yaml);
- o `Service` continua `type: LoadBalancer` com `externalTrafficPolicy: Local`;
- no estado live de 2026-04-25, o `k8s-master` era o unico node ouvindo `80/443` para a borda,
  enquanto os workers nao expunham essas portas do ingress.

## Audit Results (2026-04-26)

Auditoria completa executada em 2026-04-26. Resultados:

- **DNS**: `dnor.io` e `*.dnor.io` apontam para `3.33.130.190` e `15.197.148.33` — IPs da
  **Amazon (AS16509)**, confirmados como OCI Load Balancer provisionado na region Ashburn (IAD).
  O trafego externo **nao vai direto ao IP publico do master** (`150.136.34.254`).
- **Listeners**: tanto `k8s-master` (10.0.1.100) quanto `k8s-node-2` (10.0.1.50) estao ouvindo
  80/443 com nginx. O `ingress-nginx-controller-workers` (com affinity `NotIn: k8s-master`) ja
  esta deployado no live ha ~6h, com pod em `k8s-node-2`.
- **Service Endpoints**: o Service `ingress-nginx-controller` ja tem dois endpoints:
  `10.0.1.100:443` (master) e `10.0.1.50:443` (node-2).
- **LoadBalancer status**: `status.loadBalancer: {}` — nenhum IP externo provisionado pelo k8s.
  O OCI LB externo provavelmente encaminha para os NodePorts ou diretamente para as portas 80/443
  dos nodes dentro da VCN (via Security List/NSG).
- **IaC**: o `deploy.yaml` versionado ainda tem `nodeSelector: k8s-master` — existe drift entre
  repo e live (o `ingress-nginx-controller-workers` foi criado ad-hoc no live, nao esta no repo).

## Chosen Direction

Consolidar a IaC para refletir a topologia live, remover o `nodeSelector: k8s-master` do
deployment principal e documentar o `ingress-nginx-controller-workers` no repo.

Nao eh necessario alterar o Service ou o LoadBalancer OCI — o path de borda ja funciona com os
dois nodes ouvindo 80/443 via `hostNetwork`.

## Objective
Separar a borda HTTP/TCP do cluster da dependencia hard no `k8s-master`, sem quebrar o acesso atual a
`80/443` e sem assumir um `LoadBalancer` que nao esteja efetivamente presente.

## Tasks
- [x] Mapear o path de entrada atual para `*.dnor.io`: DNS, Tailscale/CoreDNS, IP publico, listeners
      locais e qualquer dependencia oculta do master.
- [x] Confirmar se existe ou nao um `LoadBalancer` funcional de verdade na borda: OCI LB externo
      confirmado com IPs Amazon, nao depende do IP do master diretamente.
- [x] Definir a topologia alvo do ingress fora do master: manter `ingress-nginx-controller` no
      master como fallback, adicionar `ingress-nginx-controller-workers` nos workers sem master.
- [x] Versionar `ingress-nginx-controller-workers` no `deploy.yaml` com rollback explicito.
- [x] Remover o `nodeSelector: k8s-master` do deployment principal, substituindo por affinity
      `preferred` nos workers. Ambos os deployments convergidos no live e no repo.
- [x] Validar a topologia nova: ambos os pods `1/1 Running`, endpoints do Service com os dois IPs
      (10.0.1.50 e 10.0.1.100), smoke test HTTP 200 em `dnor.io` e `nexus.dnor.io`.

## Safety Gates

- Nao remover o `ingress-nginx-controller` do master sem validar que o OCI LB continua entregando
  trafego via workers.
- O `externalTrafficPolicy: Local` no Service significa que o LB externo precisa rotear para nodes
  onde o pod do ingress realmente esta. Confirmar que o health check do OCI LB inclui os workers.

## References
- [T-150](T-150-Master-Rootfs-Dependency-Reduction.md)
- [components/ingress-nginx/deploy.yaml](../../../components/ingress-nginx/deploy.yaml)
