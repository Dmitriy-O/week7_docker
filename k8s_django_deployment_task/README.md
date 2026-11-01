# Week 8 — Task 1: Django on Kubernetes

Healthchecks runs on Amazon EKS with a private PostgreSQL database in Amazon RDS.

## Implementation

- Terraform manages the VPC, EKS, worker nodes, RDS, ECR and controller IAM resources.
- Two ARM64 t4g.small worker nodes run the Kubernetes workloads.
- The application image is stored in ECR and runs on container port 8080.
- A custom Helm chart manages configuration, encrypted application secrets,
  database CA certificates, migrations, the web Deployment, Service, HPA,
  Ingress, Issuer and Certificate.
- Migrations run as a separate Job before the web release.
- SOPS and age encrypt secret values; helm-secrets decrypts them during deployment.
- PostgreSQL connections use verify-full TLS with the AWS RDS CA bundle.
- Readiness checks database connectivity; liveness checks application responsiveness.
- Metrics Server supplies CPU and memory metrics.
- HPA scales the application between two and four replicas at an 80% target.
- AWS Load Balancer Controller provisions a public NLB for Traefik.
- Traefik routes HTTPS traffic to the application's ClusterIP Service.
- cert-manager obtains a trusted Let's Encrypt certificate using HTTP-01.
- Helmfile defines releases, environment values and deployment dependencies.

## Verification

Both health endpoints returned HTTP 200 over HTTPS with certificate verification.
The HPA test reached four replicas and subsequently returned to two.

See documentation/evidence/ and documentation/deployment_guide.md.

## Scope

This directory covers Tasks 1 and 2.

## Security

Never commit Terraform state, saved plans, decrypted secrets, database dumps,
AWS credentials or the private age key.

## Task 2: persistent static storage

Terraform provisions encrypted Amazon EFS, mount targets in both
Availability Zones, an Access Point for UID/GID 10001, and the EFS CSI
EKS add-on with Pod Identity.

The chart defines an explicit StorageClass, PV and RWX PVC.
The healthchecks-storage release seeds versioned static files from
the application image before the web release starts.

Web replicas mount the prepared static directory read-only.
Verification records file hashes and a persistent marker across
different nodes and a complete replacement of the web Pods.

Evidence: documentation/evidence/task2-*/persistence-verification.json.
