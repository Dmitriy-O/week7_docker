#!/usr/bin/env python3
"""Configure the application role without printing secrets."""

import json
from pathlib import Path
import subprocess
import time


PROJECT = Path(__file__).resolve().parents[1]
CONTEXT = "week8-healthchecks"
NAMESPACE = "healthchecks"


def run(arguments, payload=None):
    return subprocess.run(
        arguments,
        input=payload,
        text=True,
        capture_output=True,
        check=True,
    ).stdout


def kube(*arguments, payload=None):
    return run(
        ["kubectl", "--context", CONTEXT, "-n", NAMESPACE, *arguments],
        payload,
    )


def main():
    outputs = json.loads(run([
        "terraform",
        f"-chdir={PROJECT / 'terraform'}",
        "output",
        "-json",
    ]))

    if outputs["eks_cluster_name"]["value"] != CONTEXT:
        raise SystemExit("Unexpected Terraform cluster")

    application = json.loads(run([
        "sops", "--decrypt", "--output-type", "json",
        str(PROJECT / "environments/lab/secrets.enc.yaml"),
    ]))["secrets"]

    administrator = json.loads(run([
        "aws", "secretsmanager", "get-secret-value",
        "--profile", "terraform_lab_user",
        "--region", "us-east-1",
        "--secret-id", outputs["rds_master_secret_arn"]["value"],
        "--query", "SecretString",
        "--output", "text",
    ]))

    ca = {
        "apiVersion": "v1",
        "kind": "ConfigMap",
        "metadata": {
            "name": "healthchecks-rds-ca",
            "namespace": NAMESPACE,
        },
        "data": {
            "us-east-1-bundle.pem": (
                PROJECT / "helm_chart/files/us-east-1-bundle.pem"
            ).read_text(),
        },
    }
    kube("apply", "-f", "-", payload=json.dumps(ca))

    account = {
        "apiVersion": "v1",
        "kind": "ServiceAccount",
        "metadata": {
            "name": "healthchecks-db-bootstrap",
            "namespace": NAMESPACE,
        },
        "automountServiceAccountToken": False,
    }
    kube("apply", "-f", "-", payload=json.dumps(account))

    job = json.loads(kube(
        "create", "--dry-run=client", "-o", "json", "-f",
        str(PROJECT / "bootstrap/database-user-job.yaml"),
    ))

    job_name = f"database-user-bootstrap-{int(time.time())}"
    job["metadata"]["name"] = job_name
    job["metadata"]["namespace"] = NAMESPACE

    pod = job["spec"]["template"]["spec"]
    pod["serviceAccountName"] = "healthchecks-db-bootstrap"
    pod.setdefault("volumes", []).append({
        "name": "tmp",
        "emptyDir": {"sizeLimit": "64Mi"},
    })

    container = pod["containers"][0]
    container["image"] = (
        outputs["ecr_repository_url"]["value"] + ":week8-v1"
    )
    container["securityContext"]["readOnlyRootFilesystem"] = True
    container.setdefault("volumeMounts", []).append({
        "name": "tmp",
        "mountPath": "/tmp",
    })

    for variable in container["env"]:
        if variable["name"] == "DB_HOST":
            variable["value"] = outputs["rds_address"]["value"]

    secret_name = "healthchecks-db-bootstrap"
    secret = {
        "apiVersion": "v1",
        "kind": "Secret",
        "type": "Opaque",
        "metadata": {
            "name": secret_name,
            "namespace": NAMESPACE,
        },
        "stringData": {
            "ADMIN_USER": administrator["username"],
            "ADMIN_PASSWORD": administrator["password"],
            "APP_PASSWORD": application["DB_PASSWORD"],
        },
    }

    secret_created = False
    job_created = False

    try:
        kube("create", "-f", "-", payload=json.dumps(secret))
        secret_created = True

        kube("create", "-f", "-", payload=json.dumps(job))
        job_created = True

        print(
            "Bootstrap Job started; waiting for SQL and TLS checks...",
            flush=True,
        )

        try:
            kube(
                "wait",
                "--for=condition=complete",
                f"job/{job_name}",
                "--timeout=240s",
            )
        finally:
            logs = subprocess.run(
                [
                    "kubectl", "--context", CONTEXT,
                    "-n", NAMESPACE,
                    "logs", f"job/{job_name}", "--tail=80",
                ],
                text=True,
                capture_output=True,
            )
            print(logs.stdout, end="", flush=True)

        print("DATABASE_BOOTSTRAP_OK", flush=True)

    finally:
        if job_created:
            subprocess.run(
                [
                    "kubectl", "--context", CONTEXT,
                    "-n", NAMESPACE,
                    "delete", "job", job_name,
                    "--ignore-not-found", "--wait=false",
                ],
                capture_output=True,
            )

        if secret_created:
            kube(
                "delete", "secret", secret_name,
                "--ignore-not-found",
            )


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.stderr or str(error))
