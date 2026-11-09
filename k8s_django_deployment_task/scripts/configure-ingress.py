#!/usr/bin/env python3
"""Configure the lab hostname for the currently installed public NLB."""

import ipaddress
import json
from pathlib import Path
import socket
import subprocess


project = Path(__file__).resolve().parents[1]

result = subprocess.run(
    [
        "kubectl", "--context", "week8-healthchecks",
        "-n", "ingress-system",
        "get", "service", "traefik", "-o", "json",
    ],
    check=True,
    capture_output=True,
    text=True,
)

service = json.loads(result.stdout)

endpoints = (
    service.get("status", {})
    .get("loadBalancer", {})
    .get("ingress", [])
)

if not endpoints:
    raise SystemExit(
        "NLB address is not ready; rerun after provisioning completes"
    )

endpoint = endpoints[0]

if endpoint.get("hostname"):
    addresses = {
        item[4][0]
        for item in socket.getaddrinfo(
            endpoint["hostname"],
            None,
            socket.AF_INET,
            socket.SOCK_STREAM,
        )
    }
else:
    addresses = {endpoint["ip"]}

public = sorted(
    address
    for address in addresses
    if ipaddress.ip_address(address).is_global
)

if not public:
    raise SystemExit(
        "Expected a public IPv4 address for the internet-facing NLB"
    )

host = (
    "healthchecks."
    + public[0].replace(".", "-")
    + ".sslip.io"
)

values = {
    "ingress": {
        "enabled": True,
        "host": host,
        "acmeServer": "https://acme-v02.api.letsencrypt.org/directory",
    },
    "env": {
        "ALLOWED_HOSTS": "localhost,127.0.0.1,healthchecks," + host,
        "SITE_ROOT": "https://" + host,
        "SECURE_PROXY_SSL_HEADER": "HTTP_X_FORWARDED_PROTO,https",
    },
}

target = project / "environments/lab/ingress-values.yaml"
target.write_text(
    json.dumps(values, indent=2) + "\n",
    encoding="utf-8",
)

print("Ingress configured: https://" + host)
