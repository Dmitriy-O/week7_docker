# Task 1: Kubernetes Security Enhancement

## Scope

The existing Django deployment was reviewed and hardened on EKS
`week8-healthchecks`, namespace `healthchecks`.
Validation date: 9 November 2026.

## Threats and security controls

| Threat | Implemented control | Why it matters |
| --- | --- | --- |
| Application files are modified after a compromise | Read-only container root filesystem | Reduces locations where an attacker can write files |
| Processes have excessive privileges | Non-root UID/GID 10001, dropped capabilities, disabled privilege escalation, RuntimeDefault seccomp | Limits process privileges |
| Unsafe Pods are deployed | Pod Security Admission: restricted, pinned to v1.36 | Rejects incompatible Pod configurations |
| Application receives unnecessary Kubernetes credentials | Dedicated ServiceAccounts with token automount disabled | Avoids mounting an unnecessary API token |
| Users access resources beyond their duties | Namespace Roles and RoleBindings for viewer and operator | Separates read access from limited operational actions |
| Application makes unnecessary network connections | NetworkPolicy for web Pods | Restricts incoming and outgoing connections |

Non-root execution, dropped capabilities, seccomp and disabled privilege
escalation already existed in the previous chart and were retained.
Read-only roots, temporary volumes, dedicated ServiceAccounts, PSA enforcement,
user RBAC, NetworkPolicy and Helm tests were added or extended in this task.

The web, migration and static seed containers use read-only roots.
A bounded emptyDir mounted at /tmp supports temporary writes.
The static seed Job retains its required writable EFS mount.
Existing SOPS encryption, HTTPS and RDS certificate verification were retained.

## Network rules

- Allow incoming HTTP from the selected Traefik Pods in ingress-system.
- Allow incoming HTTP from the Helm test Pod of this release.
- Allow outgoing DNS to CoreDNS on UDP/TCP 53.
- Allow outgoing PostgreSQL to the database subnets on TCP 5432.
- Other web traffic is denied unless another matching policy permits it.

The policy applies to web Pods, not migration, storage or system Pods.

## Verified results

- Helm unit tests: 13 passed across three suites.
- Helm lint and git diff --check: passed.
- Namespace PSA: enforce=restricted, enforce-version=v1.36.
- Privileged Pod server dry run: rejected by Pod Security Admission.
- Viewer: can list application Pods, cannot get Secrets or list kube-system Pods.
- Operator: can patch the application scale subresource, cannot patch the full Deployment.
- VPC CNI: enableNetworkPolicy=true; aws-node rollout completed.
- Application rollout after NetworkPolicy: completed.
- Helm readiness test: HTTP 200; this endpoint checks database connectivity.
- External HTTPS readiness request: HTTP 200 with certificate verification.
- Application TCP access to Kubernetes API: connected before policy, timed out after policy.

## Repository structure

The existing k8s_django_deployment_task layout is retained instead of duplicating
the chart under the example k8s_security_enhancement directory.

- helm_chart/templates/: Kubernetes resource templates.
- helm_chart/tests/: offline Helm unit tests.
- helm_chart/templates/tests/: Helm test Pod executed in the cluster.
- environments/lab/: environment settings and SOPS-encrypted application secrets.
- terraform/: AWS infrastructure and EKS user access configuration.
- checks/: manual validation fixtures.
- scripts/: infrastructure recovery and configuration helpers.
- documentation/: implementation notes and validation results.

This structure keeps one maintained chart and separates application templates,
environment settings, infrastructure and tests. Helmfile manages separately
versioned infrastructure releases. The existing Traefik controller is retained
instead of introducing the ingress-nginx controller from the example tree.

## Limits

This is an application-focused review, not a full cluster security audit.
An unauthorized-source ingress test and the direct runtime-security script were
not confirmed in the recorded results. Image vulnerability scanning was not
performed in this task.

Read-only roots do not prevent all code execution or access to application data.
NetworkPolicy uses IP addresses, ports and Pod labels; other matching policies
can add permissions. VPC CNI standard mode can briefly allow traffic while a new
Pod's policies are being configured.
