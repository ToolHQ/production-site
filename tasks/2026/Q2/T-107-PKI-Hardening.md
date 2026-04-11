# T-107: PKI Hardening — CA Longevity, Chain Integrity & TUI Workflows

**Status**: [x] Done | **Priority**: 🔼 High | **Owner**: Infra | **Est**: 2h

## 🎯 Objective

Three compounding PKI problems were discovered on 2026-04-11 when Chrome stopped trusting
`*.dnor.io` after a CA rotation:

1. **CA too short-lived** — `dnor-root-ca` defaults to 90 days (no `duration` set). Every
   90 days the CA rotates, all leaf certs are reissued, and the trust anchor changes.
2. **Chain incomplete after renewal** — cert-manager does not include the CA cert in the
   `tls.crt` chain of leaf certs. After each renewal, all ingresses serve only the leaf cert.
   The browser can't build the trust chain even if the CA is installed.
3. **No observability** — the watchdog (`cluster_health_check.sh`) has zero cert expiry checks.

Incident cost: ~1h of debugging. Recurrence interval: every 90 days (next: ~2026-06-23).

## 🔍 Current State

| Item             | Current                            | Problem                                         |
| ---------------- | ---------------------------------- | ----------------------------------------------- |
| CA `duration`    | 90d (default, not set)             | Rotates every ~3 months                         |
| CA `renewBefore` | not set (default: 2/3)             | Renews at day 60 → Windows still has day-0 cert |
| Leaf cert chain  | leaf only (1 cert in `tls.crt`)    | Browser can't build chain                       |
| Watchdog         | no cert checks                     | No alert before expiry                          |
| TUI export       | reads `ca.crt` key ✅ (key exists) | Export works but chain fix is manual            |
| TUI auto-install | option 6 exists (WSL+Windows)      | Works but not triggered after renewal           |

## 📋 Execution Plan

### Phase 1: Extend CA Longevity

- [ ] Patch `Certificate` CR `dnor-root-ca` in `cert-manager` to add:
  ```
  duration: 8760h    # 1 year
  renewBefore: 720h  # renew 30 days before expiry (not 60 days like default)
  ```
  Command:
  ```bash
  kubectl patch certificate dnor-root-ca -n cert-manager --type=merge -p \
    '{"spec":{"duration":"8760h","renewBefore":"720h"}}'
  ```
- [ ] Update `components/cert-manager/cert-manager.yaml` (or create a separate
      `components/cert-manager/dnor-root-ca.yaml`) to reflect this — avoid config drift.
- [ ] Verify `notAfter` is ~1 year out after patch.

### Phase 2: Automatic Chain Rebuild on Renewal

The core problem: cert-manager renews a leaf cert → new `tls.crt` secret has only 1 cert.

**Solution**: a `CronJob` that runs daily, detects TLS secrets missing the CA in their chain,
and patches them automatically (same logic as the manual fix applied 2026-04-11).

- [ ] Create `components/cert-manager/chain-repair-cronjob.yaml`:
  - Runs daily at 02:00 UTC (after `backup-daily` at 01:00)
  - For each cert-manager-managed `Certificate`, get the TLS secret
  - If `tls.crt` has <2 certs: patch it to `leaf + CA` (idempotent)
  - Uses `kubectl` in-cluster via `ServiceAccount`
  - Resource: `10m` CPU / `32Mi` RAM, `bitnami/kubectl` or `alpine/k8s`
- [ ] Create RBAC: `ServiceAccount` + `ClusterRole` (get/patch secrets, get certificates)
- [ ] Test: manually delete one leaf secret and trigger the job

### Phase 3: Watchdog Cert Expiry Alerts

Add to `scripts/observability/cluster_health_check.sh`:

- [ ] Check each cert-manager `Certificate` for expiry within 30 days → `🟡 WARNING`
- [ ] Check each cert-manager `Certificate` for expiry within 7 days → `🔴 CRITICAL`
- [ ] Check that no leaf TLS secret has chain length < 2 (chain integrity check)
- [ ] Redeploy watchdog to master after changes:
  ```bash
  bash oci-k8s-cluster/scripts/observability/install_health_watchdog.sh
  ```

### Phase 4: TUI Improvements (Security Menu)

Current: option 5 = Export CA (works), option 6 = Auto-install (exists but manual).

- [ ] After export (option 5), auto-offer to install on Windows immediately (merge with opt 6)
- [ ] Add cert expiry dashboard to option 1 (Check Certs): show days remaining per cert,
      color-coded (green >30d, yellow 10-30d, red <10d)
- [ ] Add option to rebuild all chains manually (one-click version of the 2026-04-11 fix)

## ✅ Definition of Done

- [ ] CA `duration=8760h` set, `notAfter` ≥ 1 year from now
- [ ] `components/cert-manager/` has the CA Certificate CR versioned with duration
- [ ] `chain-repair-cronjob.yaml` deployed, last run successful
- [ ] `cluster_health_check.sh` reports cert expiry warnings
- [ ] TUI option 1 (Check Certs) shows days remaining
- [ ] TUI export + install flow is frictionless (export CA → installs on Windows in one step)
- [ ] Verified: browser trusts `*.dnor.io` after a simulated chain-only renewal

## 🔗 Context

- Incident 2026-04-11: Chrome `NET::ERR_CERT_DATE_INVALID` / `NET::ERR_CERT_AUTHORITY_INVALID`
  Root cause: CA rotated 2026-03-25, chain never included CA cert, old CA removed from Windows
- CA next renewal: **2026-05-24** (60 days from now) — hard deadline for Phase 1
- TUI Security Menu has option 5 (export) and 6 (auto-install) but they are disconnected
- `cluster_health_check.sh` has disk/pod checks but zero PKI checks
- Related: T-102 (Watchdog), T-106 (Backup IaC)
