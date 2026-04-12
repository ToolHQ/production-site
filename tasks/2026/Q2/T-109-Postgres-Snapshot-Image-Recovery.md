# T-109: Postgres Snapshot Job Image Recovery

**Status**: [x] Done (2026-04-12) | **Priority**: 🚨 Critical | **Owner**: Infra | **Est**: 1h

## 🎯 Objective

Restore the `postgres-auto-snapshot` CronJob so automated PVC snapshots run again without
changing the Postgres workload itself.

## 🔍 Problem Analysis

On 2026-04-12 the snapshot job was stuck with `ImagePullBackOff` in namespace `postgres`.
The failure is isolated to the helper image used by the CronJob:

- `CronJob/postgres-auto-snapshot` references `bitnami/kubectl:1.28`
- Docker Hub returns `404` for that tag now
- The workload never starts, so no snapshot is created and retention cleanup never runs
- Critical Postgres pods (`postgres-0`, `postgres-1`) remain healthy; the break is limited
  to backup automation

The cluster already runs another lightweight maintenance CronJob (`chain-repair`) with
`bitnami/kubectl:latest`, and that image pulls successfully on the same ARM64 cluster.
During live recovery another defect surfaced: the script executes with `/bin/sh` but uses
Bash-only array and arithmetic loop syntax, which causes the container to fail even after
the image starts.
One more drift surfaced after checking the live StatefulSet: the CronJob still targets the
legacy PVC name `postgres-pvc`, but the replicated topology created by T-029 now uses
`postgres-data-postgres-0` and `postgres-data-postgres-1`. The backup job must target the
primary volume path that still exists in production.
The last blocker was `kubectl apply` client-side validation inside the helper pod. It tried
to fetch the API OpenAPI schema from `https://10.96.0.1:443/openapi/v2` and timed out,
which is consistent with a heavily resource-constrained control plane. Creating the snapshot
object without schema validation avoids that failure mode.

## 📋 Execution Plan

- [x] Confirm the incident in-cluster and capture the failing resource details
- [x] Verify the configured image tag is the pull failure root cause
- [x] Update the snapshot CronJob manifest to a working kubectl image, compatible shell,
      and validation-safe create flow
- [x] Apply the updated manifest to the cluster
- [x] Trigger a one-off run and confirm the job can pull, start, and create a snapshot
- [x] Move task to Done in `KANBAN.md` after recovery is confirmed

## ✅ Definition of Done

- [x] `components/backup/snapshot-cronjob.yaml` no longer references the broken image tag
- [x] Live `CronJob/postgres-auto-snapshot` updated successfully
- [x] A manual test job completes and creates a fresh `VolumeSnapshot`
- [x] Automated snapshot coverage restored without disrupting Postgres pods

## 🔗 Context

- Related IaC: `components/backup/snapshot-cronjob.yaml`
- Related RBAC: `components/backup/snapshot-automation-rbac.yaml`
- Related task: `T-106` codified the backup manifests, including this CronJob
- Comparable working CronJob: `components/cert-manager/chain-repair-cronjob.yaml`

## ✅ Recovery Notes

- Manual validation job `postgres-auto-snapshot-manual-171808` completed successfully
- Fresh snapshot `auto-20260412-171810` reached `readyToUse=true`
- Temporary debug snapshot was removed after validation to keep the namespace clean
