# Task T-003: Create Architecture Documentation

**Status**: ✅ Done
**Epic**: Documentation
**Estimate**: 2 hours

## Description
Create a visual and descriptive guide of the cluster's architecture. This will serve as the "Map" for both human engineers and AI agents to understand how components interact (Ingress -> Services -> Storage).

## Plan
1.  **Analyze current state**: Use `kubectl` to map Ingress rules, Services, and Storage interactions.
2.  **Draft Mermaid Diagrams**:
    - High-Level Topology (Nodes, Control Plane).
    - Networking Flow (Internet -> Ingress -> Pods).
    - Storage Layer (Longhorn vs Local).
3.  **Create `docs/ARCHITECTURE.md`**: Combine diagrams with concise text.

## Acceptance Criteria
- [ ] `docs/ARCHITECTURE.md` exists.
- [ ] Contains at least 2 Mermaid diagrams.
- [ ] accurately reflects the `node-3` addition.
