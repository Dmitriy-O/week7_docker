#!/usr/bin/env bash
set -euo pipefail

chart="k8s_django_deployment_task/helm_chart"
environments="k8s_django_deployment_task/environments"
output="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/healthchecks-rendered"

mkdir -p "$output"

common=(
  --namespace healthchecks
  --kube-version "${KUBERNETES_VERSION:-1.36.0}"
  --set-string secrets.DB_PASSWORD=render-only
  --set-string secrets.SECRET_KEY=render-only
)

helm lint "$chart" --strict "${common[@]}"

helm template healthchecks "$chart" "${common[@]}" \
  > "$output/defaults.yaml"

found=0

for directory in "$environments"/*; do
  [[ -f "$directory/values.yaml" ]] || continue

  found=1
  name="$(basename "$directory")"
  values=(-f "$directory/values.yaml")

  for extra in ingress-values.yaml storage-values.yaml; do
    if [[ -f "$directory/$extra" ]]; then
      values+=(-f "$directory/$extra")
    fi
  done

  for workload in web migration storage; do
    echo "Checking environment=$name workload=$workload"

    args=(
      "${common[@]}"
      "${values[@]}"
      --set "workload=$workload"
    )

    helm lint "$chart" --strict "${args[@]}"

    helm template "healthchecks-$workload" "$chart" "${args[@]}" \
      > "$output/$name-$workload.yaml"
  done
done

if [[ "$found" != 1 ]]; then
  echo "FAIL: no environments found" >&2
  exit 1
fi

echo "Rendered manifests: $output"
