# Hetzner BuildKit disk guardrails (T-311)

O builder remoto `hetzner-builder` (`hetzner-cax21-helsinki-4vcpu-8gb-ipv4`, 75G `/`) acumula cache BuildKit no volume Docker `buildx_buildkit_hetzner-builder0_state`. Sem política, o disco chegou a **90%** (~39G no volume).

## Política

| Variável | Default | Ação |
|----------|---------|------|
| `MAX_USED_PCT` | 75 | Se rootfs ≥ threshold → reset container+volume |
| `MAX_BUILDKIT_GB` | 16 | Se `/var/lib/buildkit` ≥ threshold → reset |
| Timer | 6h | 00:30, 06:30, 12:30, 18:30 UTC |

Fluxo a cada execução:

1. `docker buildx prune --all --force --max-storage 16gb`
2. Medir uso em `/var/lib/buildkit` dentro do container
3. Se ainda acima dos thresholds → `docker rm -f buildx_buildkit_hetzner-builder0` + `docker volume rm …_state`
4. Próximo deploy recria o builder via `setup-hetzner-builder.sh`

## Instalação (IaC)

```bash
cd ~/production-site-cursor
./oci-k8s-cluster/scripts/hetzner/install_buildkit_guardrails.sh
# opcional: teste sem efeito
./oci-k8s-cluster/scripts/hetzner/install_buildkit_guardrails.sh --dry-run-test
```

O `setup-hetzner-builder.sh` chama o install automaticamente (best-effort; requer `sudo` sem senha no host ou install manual como root).

## Validação

```bash
bash scripts/harness/validate_hetzner_buildkit_guardrails.sh
ssh hetzner-cax21-helsinki-4vcpu-8gb-ipv4 "df -h /; tail -5 /var/log/buildkit-guardrails.log"
```

## Emergência manual

```bash
ssh hetzner-cax21-helsinki-4vcpu-8gb-ipv4
sudo /usr/local/bin/buildkit_guardrails.sh --dry-run   # preview
sudo /usr/local/bin/buildkit_guardrails.sh             # aplicar
# ou reset agressivo:
docker buildx prune --all --force
docker rm -f buildx_buildkit_hetzner-builder0
docker volume rm buildx_buildkit_hetzner-builder0_state
# na máquina dev:
./oci-k8s-cluster/scripts/setup-hetzner-builder.sh
```

## Quem escreve no builder

Deploys ARM64 via `deploy-buildx.sh` / `deploy.sh` com `--builder hetzner-builder --load` (ai-radar, agent-meter, back-end, etc.). Cache persiste no volume BuildKit entre builds; `--load` traz só a imagem final ao dev, mas layers ficam na Hetzner.
