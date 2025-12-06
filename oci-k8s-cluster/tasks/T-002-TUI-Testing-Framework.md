# Task T-002: Implement BATS Testing Framework

**Status**: ✅ Done
**Epic**: Quality / DX
**Estimate**: 4 hours

## Description
The TUI (`k8s_ops_menu.sh`) is mission-critical but lacks regression testing. We will implement BATS (Bash Automated Testing System) to test logic functions without requiring a live cluster for everything.

## Plan
1.  **Install BATS**: Create `testing/setup_bats.sh` to install locally (node_modules or git submodule).
2.  **Scaffold Tests**: Create `testing/k8s_ops_menu.bats`.
3.  **Refactor for Testability**: Identify "pure functions" in the TUI (e.g., parsers, validators) that can be easily tested.
4.  **Write Initial Tests**:
    - Verify input validation logic.
    - Verify detailed parsing logic (e.g., `common.sh` array handling).

## Acceptance Criteria
- [ ] BATS installed and running via `npm test` or `./run_tests.sh`.
- [ ] At least 5 meaningful tests passing.
