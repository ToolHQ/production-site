# T-127 Longhorn Cleanup Plan

Date: 2026-04-18

Approved destructive action for T-127: delete stale Longhorn `BackupVolume` custom resources that no longer map to any live Longhorn volume.

Validated impact:

- No live `volumes.longhorn.io` object exists for these candidates.
- Active ETCD and GDrive cleanup is already complete.
- Remaining storage recovery opportunity is limited to historical backup generations.

Resources to delete:

- `pvc-9457cf3d-b57a-4148-9935-922998049c99-669c56db`
- `pvc-6a1e78ec-ca37-4d2d-91ae-61eb15be0e3a-cba058d6`
- `pvc-527009d1-6f72-4e1d-91e7-7bf74a60bd09-588a301f`
- `pvc-07028b00-5d63-4112-84e9-126faee4f6ce-dcd6f095`
- `pvc-b48937cd-c9ee-40e1-ab42-ddc5b3130478-b15387c2`
- `pvc-70ca900b-bf13-4b79-9cc7-91e35dc06f71-6bbe5f97`
- `pvc-024bef7e-a0a8-49cc-8632-f8827260217c-a3992f3a`
- `pvc-76d32043-c899-4346-a276-c4ad0b20a030-18ed1d6e`
- `pvc-8849d366-6900-489d-94bd-88e17ef269f9-3864eddf`
- `pvc-587154bf-86a4-40d4-8339-f33a0e082fd5-f539450f`
- `pvc-c6f50016-a36d-410b-bc17-292f9e4ff805-91f2261f`

Expected result:

- `11` stale `BackupVolume` CRs removed.
- `88` inherited backups eligible for purge.
- Approximately `5.57 GiB` of stale backup payload released from the Longhorn target over time.

Execution result:

- Applied on 2026-04-18.
- Residual stale comparison returned empty.
- Longhorn inventory converged to `8` `BackupVolume` for `8` live volumes.
