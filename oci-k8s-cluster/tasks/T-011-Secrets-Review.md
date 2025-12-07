# Task T-011: Secrets & GitOps Audit

**Status**: 🧊 Backlog
**Epic**: Security
**Estimate**: 2 hours

## Description
Audit the repository for leaked secrets and ensure robust ignoring of sensitive files. The user flagged `kubeconfig` files being created in the root.

## Actions
1.  **Audit .gitignore**: Ensure `*.conf`, `kubeconfig*`, `*.key`, `*.pem`, `*.crt` are ignored.
2.  **Scan Repo**: Check for accidentally committed secrets.
3.  **Refactor Secrets**: Move any hardcoded secrets in scripts (if any) to `credstore.sh`.
4.  **Policy**: Define a clear "Secrets in Git" policy in `AI_CONTEXT.md`.

## Immediate Fixes
- Ignore `kubeconfig_fresh.yaml`.
- Ignore `pixie_install_debug.sh` (if contained tokens).
