#!/usr/bin/env python3
"""Gera artefatos do Node Fleet a partir de config/external-fleet/registry.yaml."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError as exc:  # pragma: no cover
    raise SystemExit("PyYAML ausente. Instale: pip install pyyaml") from exc


def slugify(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")


def load_registry(path: Path) -> dict[str, Any]:
    with path.open() as handle:
        return yaml.safe_load(handle)


def write_exporter_manifest(node: dict[str, Any], out_dir: Path) -> None:
    service = node["exporter_service"]
    host = node["instance_host"]
    content = f"""# Gerado por scripts/aws-fleet/generate_fleet_artifacts.py — não editar manualmente.
apiVersion: v1
kind: Service
metadata:
  name: {service}
  namespace: coroot
  labels:
    app: {service}
    app.kubernetes.io/part-of: coroot
    app.kubernetes.io/component: node-exporter
    external-fleet/provider: {node.get('provider', 'unknown')}
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9100"
spec:
  ports:
    - name: metrics
      port: 9100
      targetPort: 9100
      protocol: TCP
---
apiVersion: v1
kind: Endpoints
metadata:
  name: {service}
  namespace: coroot
  labels:
    app: {service}
subsets:
  - addresses:
      - ip: {host}
    ports:
      - name: metrics
        port: 9100
        protocol: TCP
"""
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / f"{node['id']}-exporter.yaml").write_text(content)


def write_honeypot_metrics_manifest(node: dict[str, Any], out_dir: Path) -> None:
    if not node.get("honeypot") or not node.get("metrics_path"):
        return

    service = f"{node['id']}-honeypot-metrics"
    host = node["instance_host"]
    metrics_path = node["metrics_path"]
    content = f"""# Gerado por scripts/aws-fleet/generate_fleet_artifacts.py — não editar manualmente.
apiVersion: v1
kind: Service
metadata:
  name: {service}
  namespace: coroot
  labels:
    app: {service}
    app.kubernetes.io/part-of: coroot
    app.kubernetes.io/component: honeypot-metrics
    external-fleet/provider: {node.get('provider', 'unknown')}
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/scheme: "https"
    prometheus.io/port: "443"
    prometheus.io/path: "{metrics_path}"
spec:
  ports:
    - name: metrics
      port: 443
      targetPort: 443
      protocol: TCP
---
apiVersion: v1
kind: Endpoints
metadata:
  name: {service}
  namespace: coroot
  labels:
    app: {service}
subsets:
  - addresses:
      - ip: {host}
    ports:
      - name: metrics
        port: 443
        protocol: TCP
"""
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / f"{node['id']}-honeypot-metrics.yaml").write_text(content)


def write_external_nodes_json(nodes: list[dict[str, Any]], out_path: Path) -> None:
    payload = []
    for n in nodes:
        entry: dict[str, Any] = {
            "id": n["id"],
            "instance_host": n["instance_host"],
            "fallback_name": n["fallback_name"],
            "cluster": n["cluster"],
            "role": n["role"],
            "cpu_millicores": int(n["cpu_millicores"]),
            "memory_bytes": int(n["memory_bytes"]),
            "ephemeral_storage_bytes": int(n["ephemeral_storage_bytes"]),
        }
        if n.get("honeypot"):
            entry["honeypot"] = True
        if n.get("threats_path"):
            entry["threats_path"] = n["threats_path"]
        if n.get("timeseries_path"):
            entry["timeseries_path"] = n["timeseries_path"]
        payload.append(entry)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(payload, indent=2) + "\n")


def patch_common_sh(repo_root: Path, nodes: list[dict[str, Any]]) -> None:
    common_sh = repo_root / "oci-k8s-cluster" / "common.sh"
    text = common_sh.read_text()
    begin = "# BEGIN EXTERNAL_FLEET_NODES"
    end = "# END EXTERNAL_FLEET_NODES"

    lines = ["EXTERNAL_NODES=("]
    for node in nodes:
        alias = node.get("ssh_alias") or node["fallback_name"]
        comment = f"{node['cluster']} @ {node['instance_host']}"
        lines.append(f'  "{alias}"  # {comment}')
    lines.append(")")

    block = "\n".join([begin, *lines, end])
    pattern = re.compile(
        rf"{re.escape(begin)}.*?{re.escape(end)}",
        re.DOTALL,
    )
    if not pattern.search(text):
        raise SystemExit(f"Marcadores {begin}/{end} ausentes em {common_sh}")

    common_sh.write_text(pattern.sub(block, text, count=1))


def patch_harness(repo_root: Path, nodes: list[dict[str, Any]]) -> None:
    harness = repo_root / "scripts" / "harness" / "validate_rs_observability_live.sh"
    text = harness.read_text()
    clusters = sorted({n["cluster"] for n in nodes})
    ips = [n["instance_host"] for n in nodes]
    cluster_literal = ", ".join(json.dumps(c) for c in clusters)
    ips_literal = ", ".join(json.dumps(ip) for ip in ips)

    new_block = f"""external = [
    n for n in nodes
    if n.get("cluster") in ({cluster_literal}) or n.get("ip") in ({ips_literal})
]"""

    pattern = re.compile(
        r"external = \[\n    n for n in nodes\n    if n\.get\(\"cluster\"\).*?\n\]",
        re.DOTALL,
    )
    if not pattern.search(text):
        raise SystemExit("Bloco external do harness não encontrado")

    harness.write_text(pattern.sub(new_block, text, count=1))


def write_cluster_css(repo_root: Path, nodes: list[dict[str, Any]]) -> None:
    css_path = repo_root / "apps" / "rs-observability-api" / "web-v2" / "src" / "generated" / "cluster-badges.css"
    css_path.parent.mkdir(parents=True, exist_ok=True)

    palette = {
        "HETZNER": ("234, 88, 12"),
        "SSD-NODES": ("139, 92, 246"),
        "AWS-EC2": ("255, 153, 0"),
    }

    chunks = [
        "/* Gerado por scripts/aws-fleet/generate_fleet_artifacts.py — não editar manualmente. */",
    ]
    seen: set[str] = set()
    for node in nodes:
        cluster = node["cluster"]
        if cluster in seen:
            continue
        seen.add(cluster)
        rgb = palette.get(cluster, "100, 116, 139")
        slug = slugify(cluster)
        chunks.append(
            f".node-cluster-badge--{slug} {{\n"
            f"  background: rgba({rgb}, 0.1);\n"
            f"  color: rgb({rgb});\n"
            f"  border: 1px solid rgba({rgb}, 0.3);\n"
            f"}}"
        )

    chunks.append(
        ".node-cluster-badge--external {\n"
        "  background: rgba(100, 116, 139, 0.1);\n"
        "  color: rgb(100, 116, 139);\n"
        "  border: 1px solid rgba(100, 116, 139, 0.3);\n"
        "}"
    )
    css_path.write_text("\n\n".join(chunks) + "\n")


def write_readme(repo_root: Path, nodes: list[dict[str, Any]]) -> None:
    readme = repo_root / "components" / "observability" / "external-fleet" / "README.md"
    readme.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# External Fleet — Prometheus Endpoints",
        "",
        "Manifests gerados automaticamente. Fonte: `config/external-fleet/registry.yaml`.",
        "",
        "## Aplicar no cluster",
        "",
        "```bash",
        "kubectl apply -f components/observability/external-fleet/generated/",
        "```",
        "",
        "## Nós registrados",
        "",
    ]
    for node in nodes:
        lines.append(
            f"- **{node['id']}** — `{node['cluster']}` @ `{node['instance_host']}` (`{node['exporter_service']}`)"
        )
        if node.get("honeypot") and node.get("metrics_path"):
            lines.append(
                f"  - honeypot metrics: `{node['id']}-honeypot-metrics` → `{node['metrics_path']}` (HTTPS :443)"
            )
    readme.write_text("\n".join(lines) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", required=True)
    parser.add_argument("--repo-root", required=True)
    args = parser.parse_args()

    registry_path = Path(args.registry)
    repo_root = Path(args.repo_root)
    data = load_registry(registry_path)
    nodes: list[dict[str, Any]] = data.get("nodes", [])

    out_dir = repo_root / "components" / "observability" / "external-fleet" / "generated"
    for stale in out_dir.glob("*-exporter.yaml"):
        stale.unlink()

    for node in nodes:
        write_exporter_manifest(node, out_dir)
        write_honeypot_metrics_manifest(node, out_dir)

    write_external_nodes_json(
        nodes,
        repo_root / "apps" / "rs-observability-api" / "config" / "external_nodes.json",
    )
    patch_common_sh(repo_root, nodes)
    patch_harness(repo_root, nodes)
    write_cluster_css(repo_root, nodes)
    write_readme(repo_root, nodes)

    print(f"[generate] nodes={len(nodes)} manifests={out_dir}")


if __name__ == "__main__":
    main()
