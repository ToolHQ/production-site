# T-105: Internal Registry (Nexus) Resilience

**Status**: ✅ Done | **Priority**: 🔽 Medium | **Owner**: Infra | **Est**: 2h

## 🎯 Objective

Any workload using images from the internal Nexus registry (`registry.local:31444`) depends
on Nexus being reachable at the moment a pod is scheduled on a node that doesn't have the
image cached. This happened on 2026-04-03: after a scale-down/up cycle, `postgres-1` was
scheduled on a node without the cached image, and Nexus was still initializing → ErrImagePull.

Ensure that critical stateful workloads can restart on any node regardless of Nexus availability,
by guaranteeing images are pre-cached across all worker nodes.

## 🔍 Problem Analysis

### What actually happened

postgres already uses `imagePullPolicy: IfNotPresent`. The ErrImagePull on `postgres-1` on
2026-04-03 was NOT caused by 19 days of Nexus downtime. The sequence was:

1. To break the volume attach deadlock, postgres was scaled to 0 replicas (both pods deleted)
2. Scaled back to 2 replicas — `postgres-1` was scheduled on `k8s-node-2`
3. The image `registry.local:31444/.../postgres:16-alpine-6d98ea7` was **not cached on node-2**
   (pod was freshly assigned there; `IfNotPresent` only helps if the image was previously pulled
   on that specific node)
4. Nexus had just come back up and was still initializing (Java startup ~2–3 min) → pull failed

The real gap: **images are only cached on nodes where they were previously run**. If a pod
migrates to a new node (after scale-down/up, node drain, rescheduling), it will pull again.

### Dependency Chain (corrected)

```
scale-down → scale-up → pod scheduled on node without cached image
→ Nexus still initializing → ErrImagePull (resolved within ~3 min)
```

### Affected workloads (need verification)

Images from `registry.local:31444` (Nexus Docker registry):

- `postgres` — confirmed, uses internal image with versioned tag ✓
- `back-end`, `py-back-end`, `rs-axum-back-end` — likely use internal registry (verify)
- Any image built locally and pushed to Nexus

### Non-affected

Pods using public images directly (`registry.k8s.io`, `docker.io`) — these pull directly
and don't depend on Nexus availability.

## 📋 Execution Plan

### Phase 1: Audit Image Pull Sources

- [x] List all running pods and their image sources: `kubectl get pods -A -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}' | sort -u`
- [x] Classify each image: public registry vs `registry.local` vs `nexus.dnor.io`
- [x] Identify critical stateful workloads that use internal images (highest risk)

### Phase 2: `imagePullPolicy` Audit

postgres already uses `IfNotPresent` with versioned tags — correct. Audit remaining workloads.

- [x] Audit all Deployments/StatefulSets for `imagePullPolicy` setting
- [x] Confirm all internal-registry images use versioned (non-`latest`) tags for the active workloads — `latest` forces
      `Always` pull by default regardless of the explicit policy setting
- [x] For any active workload still using `imagePullPolicy: Always` with internal images: change to
      `IfNotPresent` and confirm it uses an immutable tag
- [x] Document findings — live workloads using `registry.local:31444` are now pinned to immutable tags and `IfNotPresent`

### Phase 3: Pre-Pull Critical Images on All Nodes

Ensure images are cached on all nodes so rescheduling never triggers a pull.

- [x] Identify all internal-registry image tags for critical stateful workloads (postgres, etc.)
- [x] **Preferred approach**: add a `pre-pull-images` option to `k8s_ops_menu.sh` under
      "Maintenance" — for each target node, run a short-lived pod with the target image and a
      matching `nodeSelector` to force the kubelet to pull and cache it:
  ```
  kubectl run pre-pull-NODE --image=registry.local:31444/.../postgres:TAG \
    --restart=Never \
    --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"k8s-node-X"}}}' \
    --command -- echo done
  kubectl delete pod pre-pull-NODE
  ```
  Run this after any Nexus restart or before a planned maintenance window.
- [x] **Avoid**: a permanent pre-pull DaemonSet — it adds a pod per node, consuming CPU
      on an already saturated cluster, for a benefit that only matters occasionally.
- [x] Verify: scale postgres to 0 then back to 2 with Nexus at 0 replicas. `postgres-1`
      must start successfully using cached image. ⚠️ Run this test only when `postgres-0` is
      confirmed Running and healthy first (replica handles traffic during the test).

### Phase 4: Nexus Health Integration

- [x] Add Nexus pod readiness to T-102 watchdog: alert if Nexus is not ready
- [x] Verify/add Nexus to TUI "Port Forward" menu with health check URL
- [x] Verify the Nexus `readinessProbe` in `components/nexus/nexus.yaml` is properly configured
      and actually checks registry API (not just HTTP 200 on root)

## ✅ Definition of Done

- [x] All stateful workloads use `imagePullPolicy: IfNotPresent` with explicit versioned tags
- [x] Critical images (postgres, etc.) are pre-pulled on all nodes
- [x] With Nexus at 0 replicas: scale postgres to 0 then back to 2 (forces rescheduling);
      `postgres-1` must start successfully using cached image on whatever node it lands on.
      ⚠️ Run only when `postgres-0` is confirmed Running first — one replica handles traffic
      during the test. Do NOT use `kubectl delete pod postgres-0` (StatefulSet recreates on
      same node — doesn't test cross-node caching).
- [x] Nexus health included in T-102 watchdog output

## 🔗 Context

- `postgres-1` failed with `ErrImagePull` on 2026-04-03 immediately after Nexus came back up
- Nexus was down for 19 days due to the same CPU starvation cascade (T-102, T-103)
- Related: T-102 (Watchdog), T-103 (CPU Headroom)

## Update — 2026-04-20

- Live cluster audit found four active images served by the internal Docker registry: `my-site-back-end`, `my-site-nginx`, `postgres` and `torproxy`.
- `postgres` was already correct (`IfNotPresent` + immutable tag). The three active Deployments in `default` still used immutable tags but were configured with `imagePullPolicy: Always`; the live Deployments and repo manifests were updated to `IfNotPresent`.
- The TUI already contained the maintenance action **Pre-Pull Internal Images on All Nodes** in `k8s_ops_menu.sh`; this session revalidated the workflow and executed a full pre-pull across `k8s-node-1`, `k8s-node-2` and `k8s-node-3` for all four internal images, with 12/12 short-lived pulls completing successfully.
- The watchdog in `cluster_health_check.sh` was already checking Nexus pod readiness. This session also validated the practical API endpoint from inside the Nexus pod: `http://127.0.0.1:8081/service/rest/v1/status` returns `HTTP/1.1 200 OK`, while `http://127.0.0.1:18444/v2/` returns `401 Unauthorized` when healthy.
- Based on that live validation, `components/nexus/nexus.yaml` was updated to use `startupProbe` and `readinessProbe` against `/service/rest/v1/status` on port `8081`, which is a real Nexus API endpoint rather than a shallow root-page check.
- The approved destructive verification drill was executed after confirming `postgres-0`/`postgres-1` were healthy and `nexus-deployment` was `1/1 Ready`.
- `nexus-deployment` was scaled to `0`, both `postgres` pods were scaled to `0`, and the StatefulSet was restored to `2` replicas while Nexus stayed offline.
- `postgres-0` and `postgres-1` both returned `1/1 Running` without any `ErrImagePull`; the recovered replicas landed on `k8s-node-1` and `k8s-node-3`, demonstrating the pre-pulled cache path works even with Nexus unavailable.
- `nexus-deployment` was then restored to `1/1 Running`, closing the last open acceptance item for this task.
