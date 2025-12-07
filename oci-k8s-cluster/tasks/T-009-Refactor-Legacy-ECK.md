# Task T-009: Refactor Legacy ECK Components

**Status**: ✅ Done
**Epic**: Refactoring / Observability
**Estimate**: 4 hours

## Description
Analyze and refactor the legacy `components/eck` directory. Historically, this contained custom Logstash and Beats configurations with patterns optimized for our infrastructure (minikube/nexus era). These must be preserved and modernized.

## Directives
1.  **Analyze**: Review `components/eck/logstash`, `components/eck/quick-start-logstash.yaml`, and `components/eck/quick-start-beats.yaml`.
2.  **Extract Patterns**: Identify the Grok patterns and pipeline logic that are valuable.
3.  **Decouple**: Ensure the new structure does not tightly couple ECK (Operator) updates with Pixie or other components. Consider splitting `components/observability` if it gets too bloated, or create `components/logging-pipelines`.
4.  **Modernize**: Adapt the manifests to the current `elastic-system` namespace and ECK Operator version.

## Goal
A clean, modular set of logging components that can be deployed independently via the TUI.
