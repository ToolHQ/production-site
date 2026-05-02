#!/usr/bin/env python3
"""Emit a Postgres DATABASE_URL for AI Radar using in-cluster postgres-secret.

Requires kubectl reachable (tunnel + KUBECONFIG). Does not modify the cluster.
"""
from __future__ import annotations

import base64
import json
import os
import subprocess
import urllib.parse


def kubectl_json(args: list[str]) -> dict:
    out = subprocess.check_output(["kubectl", *args], text=True)
    return json.loads(out)


def main() -> None:
    data = kubectl_json(
        ["get", "secret", "postgres-secret", "-n", "postgres", "-o", "json"]
    )["data"]
    raw_user = base64.b64decode(data["POSTGRES_USER"]).decode()
    raw_pass = base64.b64decode(data["POSTGRES_PASSWORD"]).decode()

    host = os.environ.get(
        "AI_RADAR_PG_HOST", "postgres-service.postgres.svc.cluster.local"
    )
    db = os.environ.get("AI_RADAR_PG_DATABASE", "postgres")

    user = urllib.parse.quote(raw_user, safe="")
    password = urllib.parse.quote(raw_pass, safe="")

    qs = "?options=-csearch_path%3Dpublic"

    print(f"postgres://{user}:{password}@{host}:5432/{db}{qs}")


if __name__ == "__main__":
    main()
