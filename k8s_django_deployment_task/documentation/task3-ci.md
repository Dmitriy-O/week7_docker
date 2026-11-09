# Task 3: Kubernetes security checks in CI

## Implementation

The project uses GitHub Actions with Helm 3.19.0 and Kubernetes
1.36.0 schemas. CI runs without access to AWS or a Kubernetes cluster.

Files:

- `.github/workflows/ci.yaml`: workflow definition.
- `ci/check-sops.py`: encrypted secrets file checks.
- `ci/render-chart.sh`: Helm linting and manifest rendering.
- `k8s_django_deployment_task/helm_chart/tests/`: security regression tests.

## Pipeline checks

The workflow runs on every pull request and on pushes to
`task-9/kubernetes-security`.

1. Check that environment secrets files contain SOPS metadata
   and encrypted secret values.
2. Run Helm lint and render chart defaults and each environment's
   web, migration and storage configurations.
3. Validate rendered manifests with kubeconform against Kubernetes
   1.36.0 schemas. cert-manager resources use schemas extracted
   from the official cert-manager CRDs.
4. Run Helm unit tests.
5. Scan rendered manifests with Trivy. HIGH and CRITICAL findings
   fail the job.

Rendering uses dummy secret values. The private age key and real
application passwords are not provided to CI.

## Passing baseline

Commit: `437c058b05a9268ffbbb8c9c62ea9be435d2a76f`

All pipeline checks passed:

https://github.com/Dmitriy-O/week7_docker/actions/runs/42600615578

## Failing security example

Branch: `task-9/ci-negative-example`

Pull request:

https://github.com/Dmitriy-O/week7_docker/pull/1

The demonstration changes readOnlyRootFilesystem from true to false
in the Django Deployment template. This weakens container protection
by allowing writes to its root filesystem.

Helm lint, rendering and Kubernetes schema validation passed because
false is a valid value. The "Run Helm unit tests" step rejected the
change because the security regression test requires true.

Result:

```text
Suite: Workload security regression checks
Test: hardens the web container and uses the dedicated account
Expected: readOnlyRootFilesystem: true
Actual: readOnlyRootFilesystem: false
Tests: 1 failed, 12 passed, 13 total
```

Failed pipeline:

https://github.com/Dmitriy-O/week7_docker/actions/runs/42601838254

The workflow was triggered by the pull_request synchronize event.
Trivy was skipped after the unit-test failure.

Keep the demonstration PR unmerged.

## Merge enforcement

To prevent merging failed changes, protect the target branch
`task-9/kubernetes-security` and require the
`Helm security checks` status check.

Require pull requests and disable bypassing the protection rules.
A failed workflow alone does not configure merge protection.

## Limitations

These checks validate files without deploying the application.
They do not verify live RBAC decisions or NetworkPolicy enforcement.

The SOPS check verifies structure and encrypted-value formatting.
Without the private key, it cannot authenticate or decrypt the contents.

Detection depends on the configured tests and scanner rules.
