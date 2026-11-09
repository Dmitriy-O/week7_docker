# Week 9 Report: Kubernetes Security, Audit Logging and CI

## 1. Project overview

The project extends an existing Django application deployed to Amazon EKS
through a Helm chart.

The work covered three areas:

1. Improving the application's Kubernetes security configuration.
2. Collecting and analyzing Kubernetes API audit events.
3. Automatically checking the Helm chart before changes are merged.

Repository:
https://github.com/Dmitriy-O/week7_docker

Working branch:
task-9/kubernetes-security


The Kubernetes infrastructure was removed after validation. The CI pipeline
continues to work without AWS infrastructure or access to a cluster.

## 2. Existing application architecture

During live validation, the application used:

- Amazon EKS for Kubernetes.
- ARM64 worker nodes using t4g.small instances.
- Amazon ECR for application images.
- Amazon RDS for PostgreSQL.
- Amazon EFS for shared static files.
- Traefik as the ingress controller.
- An AWS Network Load Balancer for external access.
- cert-manager for HTTPS certificates.
- Helm and Helmfile for deployment configuration.
- SOPS with age for encrypted application secrets.

Application traffic entered through the load balancer and Traefik, then
reached a Django Pod through the application Service.

Django connected to PostgreSQL and accessed the required static files.

# Task 1: Kubernetes Security Enhancement

## 3. Security assessment

The review focused on the application's workloads, access permissions
and network connections.

| Identified threat | Security measure |
| --- | --- |
| A compromised process modifies application files | Read-only container root filesystem |
| A process runs with excessive privileges | Non-root execution, dropped capabilities, disabled privilege escalation and seccomp |
| An unsafe Pod is deployed | Pod Security Admission with the restricted policy |
| Application Pods receive unnecessary Kubernetes credentials | Disabled ServiceAccount token automount |
| Users access resources outside their responsibilities | Namespace-scoped RBAC |
| Application Pods make unnecessary network connections | NetworkPolicy |
| A future chart change weakens these controls | Helm security regression tests |

Non-root execution, dropped capabilities, seccomp and disabled privilege
escalation already existed in the previous chart and were retained.

The task added or extended read-only roots, temporary volumes,
ServiceAccounts, Pod Security Admission, user RBAC, NetworkPolicy and tests.

## 4. Workload hardening

The web Deployment, migration Job and static seed Job use hardened
container settings.

Pod-level settings include:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  seccompProfile:
    type: RuntimeDefault
```

Container-level settings include:

```yaml
securityContext:
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

These settings limit process privileges and writable filesystem locations.

They reduce the impact of a compromise but do not prevent every form of
code execution or access to application data.

## 5. Temporary storage

A read-only root filesystem prevents ordinary writes inside the container
image filesystem.

Some processes still require temporary files, so the workloads receive
a separate writable volume mounted at `/tmp`:

```yaml
emptyDir:
  sizeLimit: 64Mi
```

This volume exists for the lifetime of the Pod. It is temporary storage,
not a backup or persistent application database.

Gunicorn uses `/tmp` for its worker temporary files.

The static seed Job also retains its required writable EFS mount.
Application root filesystem protection therefore does not prevent the Job
from copying static files to persistent storage.

## 6. ServiceAccounts

Dedicated ServiceAccounts were configured for the application releases.

Automatic Kubernetes API token mounting was disabled:

```yaml
automountServiceAccountToken: false
```

The application does not require a Kubernetes API token for its normal
HTTP and database operations.

Disabling token mounting avoids placing unnecessary API credentials
inside the application Pods.

## 7. Pod Security Admission

The application namespace was configured with:

```yaml
pod-security.kubernetes.io/enforce: restricted
pod-security.kubernetes.io/enforce-version: v1.36
```

A server-side dry run attempted to create a privileged Pod.

Kubernetes rejected the Pod because it violated the restricted policy.

This verified that the namespace policy was enforced by the API server.

Read-only root filesystems remain an additional project requirement;
they are also checked by the Helm unit tests.

## 8. Role-Based Access Control

Two user roles were configured through AWS IAM roles, EKS access entries,
Kubernetes groups, Roles and RoleBindings.

Separate kubeconfig contexts were used to test the permissions.

| Identity | Operation | Observed result |
| --- | --- | --- |
| Viewer | List application Pods | Allowed |
| Viewer | Get application Secrets | Denied |
| Viewer | List Pods in kube-system | Denied |
| Operator | Patch the application's scale subresource | Allowed |
| Operator | Patch the full application Deployment | Denied |

The operator can perform the tested scaling operation without receiving
permission to modify the entire Deployment.

The application ServiceAccounts and human user roles serve different
purposes: workloads use ServiceAccounts, while users authenticate through
their configured EKS identities.

## 9. NetworkPolicy

NetworkPolicy enforcement was enabled in the AWS VPC CNI configuration.

The application web policy allows:

- Incoming HTTP from the selected Traefik Pods in ingress-system.
- Incoming HTTP from the release's Helm test Pod.
- Outgoing DNS to CoreDNS on TCP and UDP port 53.
- Outgoing PostgreSQL traffic to the database subnets on TCP port 5432.

Other web Pod traffic is denied unless another matching policy permits it.

The policy targets the web Pods. It does not provide the same isolation
for migration, storage or Kubernetes system Pods.

A before-and-after test verified Kubernetes API connectivity:

```text
Before policy enforcement:
API_TCP_BASELINE_OK

After policy enforcement:
API_EGRESS_DENIED_OK
```

The application remained operational after the policy was applied.

## 10. Task 1 validation

The following results were recorded:

- 13 Helm unit tests passed across three suites.
- Helm lint passed.
- git diff --check passed.
- Namespace PSA labels showed restricted enforcement pinned to v1.36.
- A privileged Pod was rejected during a server-side dry run.
- Viewer and operator permissions matched the tested RBAC restrictions.
- VPC CNI NetworkPolicy support was enabled.
- The application rollout completed successfully.
- The Helm readiness test returned HTTP 200.
- External HTTPS readiness returned HTTP 200.
- The application certificate became Ready.
- Kubernetes API TCP access from the web workload was blocked after
  NetworkPolicy enforcement.

The readiness endpoint also checked database connectivity.

The direct runtime-security script and an unauthorized-source ingress
test were not confirmed in the recorded results.

# Task 2: Kubernetes Audit Logging

## 11. Logging setup

EKS exported the following control-plane log types to CloudWatch:

- api
- audit
- authenticator

The log group was:

```text
/aws/eks/week8-healthchecks/cluster
```

The Terraform configuration set retention to seven days.

Audit logging records information about API operations, including the
requesting identity, requested resource, operation and response.

This makes it possible to investigate access attempts and verify
authorization decisions.

## 12. Analysis tool

Amazon CloudWatch Logs Insights was selected for log analysis.

It allowed filtering and aggregation of the JSON audit records without
deploying additional logging Pods.

Task 2 explicitly permits a cloud provider's analysis service.

However, the assignment also contains an ELK-specific submission list.
This implementation does not include Elasticsearch, Kibana, Logstash
or Filebeat values files. Acceptance of the CloudWatch alternative must
therefore be confirmed if those exact ELK files are mandatory.

## 13. Investigation scenario

An intentional unauthorized request was made using the viewer context:

```text
Get Secret:
healthchecks/healthchecks-secrets
```

Kubernetes returned:

```text
403 Forbidden
```

The corresponding audit event was found in CloudWatch.

| Field | Recorded value |
| --- | --- |
| Request time, UTC | 2026-11-09T01:14:01.356882Z |
| Role | week8-healthchecks-viewer |
| Kubernetes group | healthchecks-viewers |
| Verb | get |
| Resource | secrets |
| Resource name | healthchecks-secrets |
| Namespace | healthchecks |
| Response code | 403 |
| Authorization decision | forbid |

This was a controlled lab exercise, not evidence of a real intrusion.

## 14. Query and findings

The denied-secrets query selected:

- Audit log streams.
- ResponseComplete events.
- The healthchecks namespace.
- Secret resource requests.
- Responses with status code 403.

Selecting ResponseComplete avoids counting multiple stages of the same
request in this analysis.

The query completed and matched one event in the selected time window.

Query ID:

```text
578fdb4c-9125-4b70-ab8e-3ebad2f14058
```

The result matched the test identity, resource and denied operation.

This confirmed that RBAC blocked the tested request and that the denial
was available for investigation.

A single denied request does not prove account compromise. A real
investigation should also examine repeated attempts, other targeted
resources and successful operations by the same identity.

## 15. Audit logging limitations

EKS uses an AWS-managed audit policy with exclusions for some system
requests.

Secret operations are recorded at Metadata level.

The implementation therefore does not claim to capture literally every
API request or every request body.

The verified evidence and queries are recorded under:

```text
k8s_audit_logging/
```

The investigation took place before the cluster was removed.

# Task 3: Security Checks in CI

## 16. Purpose

The Helm chart contains security controls, but developers can accidentally
weaken them.

The CI pipeline automatically checks proposed changes before merging.

GitHub Actions was selected because the repository is hosted on GitHub.

CI does not require:

- A running EKS cluster.
- AWS credentials.
- A kubeconfig.
- The private SOPS age key.
- Real application passwords.

## 17. Pipeline files

The implementation consists of:

- `.github/workflows/ci.yaml`
- `ci/check-sops.py`
- `ci/render-chart.sh`
- The existing Helm security unit tests.

The workflow runs on every pull request and on pushes to
`task-9/kubernetes-security`.

## 18. Pipeline checks

### SOPS file check

The Python script checks the expected environment secrets files.

It rejects missing metadata, plaintext secret values and duplicate YAML keys.

It checks structure and encrypted-value formatting. It cannot authenticate
or decrypt the contents without the private key.

### Helm lint and rendering

Helm 3.19.0 runs linting and renders:

- Chart defaults.
- Each environment's web configuration.
- Each environment's migration configuration.
- Each environment's storage configuration.

Dummy secret values are supplied during rendering.

The rendered YAML is stored in the runner's temporary directory.

### Manifest schema validation

Kubeconform validates the rendered resources against Kubernetes 1.36.0
schemas.

cert-manager resources use schemas extracted from the official
cert-manager CRDs.

Local validation found 40 resource instances across four rendered files:

```text
Valid: 40
Invalid: 0
Errors: 0
Skipped: 0
```

### Helm unit tests

The existing tests check project-specific security requirements,
including securityContext, namespace policy, RBAC and NetworkPolicy.

The passing baseline contained 13 successful tests across three suites.

### Security scanning

Trivy scans the rendered Kubernetes manifests.

HIGH and CRITICAL findings cause a non-zero exit code and fail the job.

The passing baseline contained no findings at these severity levels.

This step scans configuration. It does not perform application image
vulnerability scanning.

## 19. Successful pipeline evidence

The initial verified passing baseline was:

```text
437c058b05a9268ffbbb8c9c62ea9be435d2a76f
```

Successful baseline run:

https://github.com/Dmitriy-O/week7_docker/actions/runs/42600615578

A later run, including the submitted Task 3 report, also passed:

https://github.com/Dmitriy-O/week7_docker/actions/runs/42602341714

## 20. Deliberately failing example

A separate branch was created:

```text
task-9/ci-negative-example
```

The Deployment template was intentionally changed:

```diff
- readOnlyRootFilesystem: true
+ readOnlyRootFilesystem: false
```

The change weakens container filesystem protection while remaining valid
Kubernetes configuration.

Helm lint, rendering and schema validation passed.

The Run Helm unit tests step failed because the regression test requires
readOnlyRootFilesystem to remain true.

Recorded result:

```text
Suite: Workload security regression checks
Test: hardens the web container and uses the dedicated account

Expected:
readOnlyRootFilesystem: true

Actual:
readOnlyRootFilesystem: false

Tests: 1 failed, 12 passed, 13 total
```

Trivy was skipped because the earlier unit-test step had already failed.

Demonstration PR:

https://github.com/Dmitriy-O/week7_docker/pull/1

Failed pipeline run:

https://github.com/Dmitriy-O/week7_docker/actions/runs/42601838254

Job containing the failure details:

https://github.com/Dmitriy-O/week7_docker/actions/runs/42601838254/job/129107958463

The demonstration PR remains unmerged.

## 21. Merge protection

Branch protection was enabled for:

```text
task-9/kubernetes-security
```

The rule requires:

- A pull request before merging.
- A successful Helm security checks status check.
- Enforcement without bypassing the configured protection settings.

The demonstration PR showed the failed check as Required and the merge
button was disabled.

This verified both detection of the weakened configuration and
enforcement of the failed result at merge time.

# Repository Structure

## 22. Structure and rationale

The existing chart was retained instead of creating a second copy under
the example k8s_security_enhancement directory.

The main locations are:

- `helm_chart/templates/`: Kubernetes resource templates.
- `helm_chart/tests/`: offline Helm unit tests.
- `helm_chart/templates/tests/`: Helm test Pods executed in a cluster.
- `environments/lab/`: environment settings and encrypted secrets.
- `terraform/`: AWS infrastructure and EKS identity configuration.
- `checks/`: manual validation fixtures.
- `scripts/`: configuration and recovery helpers.
- `documentation/`: implementation reports.
- `k8s_audit_logging/`: audit queries and investigation evidence.
- `ci/`: scripts used by the CI pipeline.
- `.github/workflows/`: GitHub Actions workflows.

This structure is suitable for the project because it keeps one maintained
application chart and separates infrastructure, environment settings,
tests and documentation.

Existing Traefik deployment configuration was retained. A second ingress
controller was not introduced solely to reproduce the example directory tree.

# Final State

## 23. Infrastructure cleanup

After live validation, the restored Terraform-managed infrastructure
was removed.

The recorded cleanup result was:

```text
Apply complete!
Resources: 0 added, 0 changed, 81 destroyed.
```

Verification showed:

- Empty Terraform state resource list.
- EKS cluster not found.
- No VPC matching the project tag.

The previously created database snapshot was retained.

Task 3 continues to run independently of the deleted infrastructure.

## 24. Outcome

Task 1 improved application workload security and verified the tested
admission, access and network restrictions.

Task 2 demonstrated audit event collection and investigation using
CloudWatch Logs Insights, with the stated limitations and the
ELK-specific submission difference.

Task 3 implemented automated chart checks, demonstrated rejection of
a weakened security setting and verified that the failed required check
blocked merging.

The repository contains implementation files, reports and links to the
successful and deliberately failing CI runs.
