# T-022: OCI Rescue Operations (Cloud Integration)

**Status**: In Progress
**Owner**: Infra Team
**Priority**: 🚨 Critical (Response to Incident)

## Objectives
- [x] Implement `lib/oci_wrapper.sh` for OCI API interaction.
- [x] Implement `scripts/cloud_ops/tui_cloud.sh` for Menu Interface.
- [x] Integrate into `k8s_ops_menu.sh` (Option 22).
- [x] Implement "Smart Diagnosis" (K8s + SSH + OCI Metrics).
- [x] Implement "Post-Reboot Forensics" (journalctl analysis).

## Verification
- [ ] Automated: `verify_oci.sh` check (auth/regions).
- [ ] Manual: Diagnosis correctly identifies a healthy node.
- [ ] Manual: Diagnosis correctly identifies a ZOMBIE node (simulated or real).
