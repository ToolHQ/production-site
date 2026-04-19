# T-131: Helm Tunnel Kubeconfig Compatibility

**Status**: [x] Done | **Priority**: 🚨 Critical | **Owner**: Infra / DevOps | **Est**: 2h | **Closed**: 2026-04-19

## 🎯 Objective

Restore reproducible local Helm workflows for cluster-managed components when using
`oci-k8s-cluster/kubeconfig_tunnel.yaml` through the standard SSH tunnel to the control plane.

The immediate blocker was that Helm-managed component scripts (`kubecost`, `coroot`,
`kubernetes-dashboard`) were failing locally even though `kubectl` against the same tunnel
continued to work.

## 🔍 Investigation Summary

### Reproduction

- Local `kubectl` worked with the standard tunnel flow:
  - `ssh -L 6445:localhost:6443 oci-k8s-master -N -f`
  - `export KUBECONFIG=oci-k8s-cluster/kubeconfig_tunnel.yaml`
- Local system Helm failed against the same kubeconfig with:

```text
Error: Kubernetes cluster unreachable: tls: failed to parse private key
```

- The failing local client was:

```text
helm v3.14.3 (Go 1.21.7)
```

- A newer Helm binary validated locally against the exact same `kubeconfig_tunnel.yaml`:

```text
helm v3.19.0 (Go 1.24.7)
helm --kubeconfig oci-k8s-cluster/kubeconfig_tunnel.yaml list -n kubecost  # success
```

- Helm on the master also worked with `/etc/kubernetes/admin.conf`:

```text
helm v3.19.0 list -n kubecost  # success on master
```

### What was ruled out

- Not a broken tunnel: `kubectl` continued to reach the API server through `127.0.0.1:6445`.
- Not an invalid client certificate or mismatched key:
  - the tunnel kubeconfig key and cert are valid RSA 2048 material;
  - the public key derived from the local key matches the public key in the client certificate;
  - the same client certificate public key is used by the working admin credentials on the master.
- Not a patch-file or IaC pathing issue: the same failure reproduced even in direct Helm CLI tests,
  before component scripts were involved.
- Not an inline-vs-file kubeconfig issue: converting the tunnel kubeconfig to temporary
  file-referenced `client-certificate` / `client-key` form still failed under Helm `v3.14.3`.

### Root Cause

The operational root cause is local Helm client compatibility, not cluster credential corruption.

`helm v3.14.3` fails against this tunnel kubeconfig/client-key combination, while `helm v3.19.0`
works against the same cluster path. For repo operations, the safe conclusion is:

- local Helm versions older than `v3.19.0` are not reliable with `kubeconfig_tunnel.yaml`;
- the repo must not assume the workstation's system Helm is sufficiently new.

## ✅ Remediation Applied

### 1. Added a compatible Helm wrapper

New helper:

- `tools/helm_compat.sh`

Behavior:

- uses system Helm when it is already `>= v3.19.0`;
- otherwise downloads and caches a compatible Helm release under
  `${XDG_CACHE_HOME:-$HOME/.cache}/production-site/helm/...`;
- executes the compatible binary transparently for repo workflows.

### 2. Wired active Helm-managed component scripts to the wrapper

- `components/kubecost/commands.sh`
- `components/coroot/commands.sh`
- `components/kubernetes-dashboard/commands.sh`

This removes dependence on the workstation's preinstalled Helm version.

### 3. Validation

- `./tools/helm_compat.sh version` returned `v3.19.0`
- `./tools/helm_compat.sh list -n kubecost` succeeded against `kubeconfig_tunnel.yaml`
- `./components/kubecost/commands.sh` succeeded from the repo root and upgraded the release to
  revision `13`

### 4. End-to-end follow-up

Post-wrapper validation across the other active Helm-managed workflows confirmed that the
original tunnel/kubeconfig problem was resolved and exposed two unrelated downstream blockers:

- `components/kubernetes-dashboard/commands.sh` was still using the dead chart repo URL
  `https://kubernetes.github.io/dashboard/` and its local `values.yaml` no longer matched the
  current 7.x chart schema.
- `components/coroot/commands.sh` was no longer blocked by Helm compatibility; instead,
  `coroot-prometheus-server` was crashing because its Longhorn PVC had filled to `100%` and the
  Prometheus process faulted during `queries.active` mmap initialization.

Applied follow-up fixes:

- switched the Dashboard workflow to the official GitHub release chart tarball
  (`kubernetes-dashboard-7.14.0.tgz`) and aligned the repo values file with the chart's real
  `api/auth/web/metricsScraper.*.containers.resources` schema;
- corrected the post-Helm Dashboard patch targets to the actual deployment names
  (`kubernetes-dashboard-*`);
- increased Coroot Prometheus PVC size from `2Gi` to `4Gi` and added
  `storage.tsdb.retention.size=1500MB` alongside the existing 1-day retention window.

Follow-up validation result:

- `./components/kubernetes-dashboard/commands.sh` succeeded and upgraded the release to
  revision `57`; all Dashboard deployments were `1/1 Running`.
- `./components/coroot/commands.sh` succeeded and upgraded the release to revision `10`;
  `coroot-prometheus-server` recovered to `2/2 Running`.

## 📋 Execution Log

- [x] Reproduced local Helm failure with `kubeconfig_tunnel.yaml`
- [x] Confirmed `kubectl` path still worked through the same tunnel
- [x] Verified newer Helm (`v3.19.0`) succeeds locally against the same kubeconfig
- [x] Verified Helm on the master succeeds with `/etc/kubernetes/admin.conf`
- [x] Ruled out bad cert/key material and inline-vs-file kubeconfig encoding as primary causes
- [x] Added `tools/helm_compat.sh`
- [x] Updated active Helm-managed component scripts to use the wrapper
- [x] Validated the repaired `kubecost` workflow from the repo root
- [x] Validated the repaired `kubernetes-dashboard` workflow from the repo root
- [x] Validated the repaired `coroot` workflow from the repo root after fixing the downstream
  storage blocker

## 🔗 Files

- `tools/helm_compat.sh`
- `components/kubecost/commands.sh`
- `components/coroot/commands.sh`
- `components/coroot/values.yaml`
- `components/kubernetes-dashboard/commands.sh`
- `components/kubernetes-dashboard/values.yaml`
- `oci-k8s-cluster/kubeconfig_tunnel.yaml`

## Notes

- This task fixes the repo workflow without forcing a system-wide Helm upgrade on the workstation.
- `kubectl` and Helm no longer need to be treated symmetrically for tunnel troubleshooting:
  `kubectl` can work while an outdated local Helm still fails.
