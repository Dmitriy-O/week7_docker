# Deployment guide — Task 1

## Deployment sequence

1. Configure the AWS profile and verify the account and region.
2. Initialize, validate and review the Terraform plan.
3. Apply Terraform to create networking and the EKS cluster.
4. Configure kubectl using the dedicated week8-healthchecks kubeconfig.
5. Verify that both worker nodes and the system Pods are Ready.
6. Build the ARM64 application image and push its versioned tag to ECR.
7. Create private RDS PostgreSQL and its security group.
8. Verify DNS and TCP connectivity from a Kubernetes Job.
9. Generate application credentials and store them in a SOPS-encrypted values file.
10. Bootstrap the hc database role using temporary administrative credentials.
    Remove the bootstrap Job and administrative Secret afterward.
11. Deploy migrations and the application using the custom chart.
12. Install Metrics Server and verify the metrics API.
13. Enable and test HPA scaling from two to four replicas.
14. Create the load balancer controller IAM role and Pod Identity association.
15. Install AWS Load Balancer Controller, Traefik and cert-manager.
16. Resolve a public NLB IPv4 address and generate a temporary sslip.io hostname.
17. Deploy the Ingress, ACME Issuer and Certificate.
18. Wait for Certificate Ready and verify HTTPS without disabling TLS verification.

## Helmfile

The environment is defined in helmfile.yaml.gotmpl at the task directory root.

Run from the repository root:

    export KUBECONFIG="$HOME/.kube/week8-healthchecks.yaml"
    export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/week8-healthchecks.txt"
    export HELM_SECRETS_DECRYPT_SECRETS_IN_TMP_DIR=true

    helmfile -f k8s_django_deployment_task/helmfile.yaml.gotmpl -e lab lint
    helmfile -f k8s_django_deployment_task/helmfile.yaml.gotmpl -e lab sync

The web release depends on migrations, Metrics Server, Traefik and cert-manager.
Traefik depends on AWS Load Balancer Controller.

## Request flow

The browser connects over HTTPS to the public AWS NLB.
The NLB forwards TCP traffic to Traefik, where TLS terminates.
Traefik forwards the HTTP request to the application ClusterIP Service.
The Service selects a ready application Pod listening on port 8080.
Django connects to private RDS using certificate and hostname verification.

SECURE_PROXY_SSL_HEADER makes Django recognize HTTPS terminated by Traefik.

## Verification

- Both EKS worker nodes reached Ready.
- The remote database passed DNS, TCP, SQL and TLS checks.
- The migration Job completed successfully.
- Both application replicas became Ready.
- Liveness remained HTTP 200 during the local database outage test.
- Readiness returned HTTP 503 during that outage and recovered to HTTP 200.
- HPA reached four replicas under load; the final state returned to two.
- The production ACME certificate reached Ready.
- HTTPS liveness and readiness returned HTTP 200 with normal certificate validation.

Evidence is stored in documentation/evidence/.

## Problems and solutions

- AWS AccessDenied: add the required actions to appropriately scoped IAM policies.
  Distinguish the Terraform caller's permissions from runtime controller permissions.
- IAM node role name prefix too long: configure a shorter explicit role name.
- Terraform local values: declare with a locals block and reference with local.name.
- DNS lookup failure: restore network/DNS connectivity before retrying Terraform.
- Saved plan stale: generate a fresh plan after state changes.
- State locked by an active apply: let that operation finish or interrupt it gracefully.
- Worker creation failed: Auto Scaling reported t4g.medium ineligible for this account.
  Query eligible instance types and replace the failed node group with t4g.small.
- Incorrect Docker push destination in zsh: use braces around the repository variable
  before the colon and image tag.
- SOPS identity not found: set SOPS_AGE_KEY_FILE to the existing private age key.
- Helm unexpected EOF: close the template conditional with its matching end.
- No owned domain: use an IP-based sslip.io hostname for this temporary lab.

## Benefits and limits

Kubernetes replaces failed Pods, routes traffic to ready instances, supports rolling
updates and scales application replicas. Helm packages related resources and
provides versioned releases. Helmfile defines the environment and dependencies.

HPA changes application replica counts; it does not add worker nodes.
Worker count is fixed at two. Resource and Pod capacity remain finite.
The database is Single-AZ, so this lab is not a fully highly available production setup.
The temporary hostname points to one NLB address and does not provide DNS failover.

## Backup and teardown

Before deletion, save verification evidence and an age-encrypted pg_dump archive.
The dump contains the hc database; recreate its login role separately during recovery.
Keep the private age key outside Git. An archive listing check is not a restore test.

Delete the public Ingress and Traefik LoadBalancer Service while AWS Load Balancer
Controller is still running. Verify that the NLB is removed before deleting EKS.

Disable RDS deletion protection before deleting the database.
If using the verified local dump instead of a final RDS snapshot, explicitly configure
the deletion to skip that snapshot. Retained snapshots can continue to incur charges.
A nonempty ECR repository also requires explicit image deletion or force_delete.

Review and apply the Terraform destroy plan. Check for remaining lab load balancers,
NAT gateways, public IP allocations, EBS volumes, snapshots and ECR storage.
Keep Terraform state until cleanup is verified. Never commit it.

## Rebuilding

Recreate the AWS resources with Terraform. Restore normal deletion protection settings
before provisioning. Refresh kubeconfig, ECR image availability and the RDS endpoint.
Recreate the application database role using the existing encrypted application password.
Restore the encrypted database dump if preserving data, or run migrations for a clean lab.
Update environment values and regenerate the temporary hostname for the new NLB.
Deploy with Helmfile and repeat database, health, certificate and HPA checks.
