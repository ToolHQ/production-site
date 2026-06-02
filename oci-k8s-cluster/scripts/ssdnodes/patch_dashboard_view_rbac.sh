#!/usr/bin/env bash
# patch_dashboard_view_rbac.sh — T-320d: Dashboard SA view-only (remove cluster-admin).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$SCRIPT_DIR/../components/ssdnodes/kubernetes-dashboard-view-rbac.yaml"
REMOTE_HOST="ssdnodes-6a12f10c9ef11"
ACTION="apply"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)  REMOTE_HOST="$2"; shift 2 ;;
        --apply) ACTION="apply"; shift ;;
        --verify) ACTION="verify"; shift ;;
        *) echo "Uso: $0 [--host HOST] [--apply|--verify]"; exit 1 ;;
    esac
done

_SSH=(ssh -o BatchMode=yes -o ConnectTimeout=15)

case "$ACTION" in
    apply)
        scp -q "$MANIFEST" "$REMOTE_HOST:/tmp/dashboard-view-rbac.yaml"
        "${_SSH[@]}" "$REMOTE_HOST" "kubectl delete clusterrolebinding admin-user --ignore-not-found"
        "${_SSH[@]}" "$REMOTE_HOST" "kubectl apply -f /tmp/dashboard-view-rbac.yaml"
        echo "OK: admin-user bound to cluster role 'view'"
        ;;
    verify)
        del=$("${_SSH[@]}" "$REMOTE_HOST" "kubectl auth can-i delete pods --all-namespaces --as=system:serviceaccount:kubernetes-dashboard:admin-user" 2>/dev/null || true)
        get=$("${_SSH[@]}" "$REMOTE_HOST" "kubectl auth can-i get pods --all-namespaces --as=system:serviceaccount:kubernetes-dashboard:admin-user" 2>/dev/null || true)
        echo "delete pods: $del (expected: no)"
        echo "get pods:    $get (expected: yes)"
        [[ "$del" == "no" && "$get" == "yes" ]] || exit 1
        echo "OK: view-only RBAC verified"
        ;;
esac
