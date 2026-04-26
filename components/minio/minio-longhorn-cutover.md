# MinIO Longhorn Cutover Runbook

T-150 versioned cutover plan to remove `MinIO` data from `/data/minio` on the master rootfs.

## Guardrails

- Do not run this without an approved maintenance window.
- Do not run this until `/data/minio` fits the requested PVC in bytes and the Longhorn schedulable
	envelope fits the chosen replica count on the actual candidate workers.
- Do not treat raw `storageAvailable` as sufficient evidence for a `longhorn-2` cutover; validate the
	real schedulable headroom derived from `storageMaximum`, `storageReserved`, `storageScheduled` and
	`storage-over-provisioning-percentage`.
- Do not delete the legacy dataset in `/data/minio` until the new backend is validated.
- The current live baseline remains [minio-resources.yaml](minio-resources.yaml).
- The target deployment manifest is [minio-longhorn-target.yaml](minio-longhorn-target.yaml).

## Preflight

1. Confirm the capacity gate before creating any cutover resources:

```bash
ssh oci-k8s-master 'sudo du -sb /data/minio'
ssh oci-k8s-master '
	export KUBECONFIG=/etc/kubernetes/admin.conf
	OVER=$(kubectl -n longhorn-system get settings.longhorn.io storage-over-provisioning-percentage -o jsonpath="{.value}")
	kubectl -n longhorn-system get nodes.longhorn.io -o json | jq -r --argjson over "$OVER" \
		".items[] | .metadata.name as \$n | .status.diskStatus | to_entries[] | .value as \$d | [\$n, (((((\$d.storageMaximum - \$d.storageReserved) * (\$over / 100)) - \$d.storageScheduled) / 1073741824) | floor)] | @tsv"
'
```

For the current `12Gi` / `longhorn-1` target, the cutover gate is green when the source dataset fits
in the PVC and at least one worker has `≥ 12Gi` of schedulable Longhorn headroom.
`longhorn-1` (1 replica) was chosen because GDrive provides off-site coverage and no worker pair
had simultaneous `12Gi` headroom available for a `longhorn-2` replica set.

2. Create the target PVC and staging deployment shell:

```bash
kubectl apply -f components/minio/minio-longhorn-preflight.yaml
kubectl -n minio scale deploy/minio-longhorn-staging --replicas=1
kubectl -n minio rollout status deploy/minio-longhorn-staging --timeout=180s
```

3. Resolve the staging pod name:

```bash
STAGING_POD=$(kubectl -n minio get pod -l app=minio-longhorn-staging -o jsonpath='{.items[0].metadata.name}')
echo "$STAGING_POD"
```

4. Confirm the target PVC is mounted and writable:

```bash
kubectl -n minio exec "$STAGING_POD" -- df -h /data
kubectl -n minio exec "$STAGING_POD" -- sh -c 'touch /data/.t150-write-test && rm -f /data/.t150-write-test'
```

## Maintenance Window

1. Stop writes to the current MinIO pod:

```bash
kubectl -n minio scale deploy/minio-deployment --replicas=0
kubectl -n minio rollout status deploy/minio-deployment --timeout=180s
```

2. Stream-copy the dataset from the master hostPath into the staging PVC:

```bash
ssh oci-k8s-master 'sudo tar -C /data/minio -cf - .' | \
kubectl -n minio exec -i "$STAGING_POD" -- tar -C /data -xf -
```

3. Validate source vs target size:

```bash
ssh oci-k8s-master 'sudo du -sh /data/minio'
kubectl -n minio exec "$STAGING_POD" -- du -sh /data
kubectl -n minio exec "$STAGING_POD" -- find /data -maxdepth 2 -type d | sort | head -n 40
```

4. Apply the target deployment and wait for the rollout:

```bash
kubectl apply -f components/minio/minio-longhorn-target.yaml
kubectl -n minio rollout status deploy/minio-deployment --timeout=300s
kubectl -n minio get deploy,pods -o wide
```

5. Validate cluster behavior:

```bash
ssh oci-k8s-master 'df -h / /data'
kubectl -n ingress-nginx get deploy,pods -o wide
kubectl -n minio get deploy,pods -o wide
ssh oci-k8s-master 'sudo /opt/k8s-ops/cluster_health_check.sh --no-color | tail -n 60'
```

## Rollback

If the cutover fails, revert the deployment manifest and bring the legacy backend back immediately:

```bash
kubectl apply -f components/minio/minio-resources.yaml
kubectl -n minio rollout status deploy/minio-deployment --timeout=300s
```

The legacy dataset under `/data/minio` must remain untouched until the new backend is validated.
