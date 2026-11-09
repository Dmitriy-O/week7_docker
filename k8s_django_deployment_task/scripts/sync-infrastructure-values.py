#!/usr/bin/env python3
"""Copy non-secret Terraform outputs into the existing lab values files."""

import json
from pathlib import Path
import re
import subprocess


def sync_values(project, outputs):
    def value(name):
        return outputs[name]["value"]

    if value("eks_cluster_name") != "week8-healthchecks":
        raise RuntimeError("Unexpected cluster: refusing to update lab values")

    subnet_ids = value("public_subnet_ids")
    if not isinstance(subnet_ids, list) or len(subnet_ids) != 2:
        raise RuntimeError("Expected two public subnet IDs")

    updates = [
        ("aws-load-balancer-controller.yaml", "vpcId", value("vpc_id")),
        ("storage-values.yaml", "volumeHandle", value("efs_static_volume_handle")),
        (
            "traefik.yaml",
            "service.beta.kubernetes.io/aws-load-balancer-subnets",
            ",".join(subnet_ids),
        ),
        ("values.yaml", "DB_HOST", value("rds_address")),
    ]

    pending = []
    for filename, key, replacement in updates:
        if not isinstance(replacement, str) or not replacement:
            raise RuntimeError(f"Missing string value for {key}")

        path = project / "environments" / "lab" / filename
        original = path.read_text(encoding="utf-8")

        pattern = rf"^([ \t]*{re.escape(key)}[ \t]*:[ \t]*)[^\r\n]*$"
        updated, count = re.subn(
            pattern,
            lambda match: match.group(1) + json.dumps(replacement),
            original,
            flags=re.MULTILINE,
        )

        if count != 1:
            raise RuntimeError(f"Expected exactly one {key} in {path}")

        pending.append((path, original, updated))

    for path, original, updated in pending:
        if original != updated:
            path.write_text(updated, encoding="utf-8")
            print(f"Updated: {path.relative_to(project)}")
        else:
            print(f"Already current: {path.relative_to(project)}")


def main():
    project = Path(__file__).resolve().parents[1]

    result = subprocess.run(
        ["terraform", f"-chdir={project / 'terraform'}", "output", "-json"],
        check=True,
        capture_output=True,
        text=True,
    )

    sync_values(project, json.loads(result.stdout))


if __name__ == "__main__":
    main()
