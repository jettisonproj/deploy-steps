#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail


#
# Wait for the resource to be available
#
wait-for-resource() {
  local resource_path="$1"
  local new_tag="$2"

  kind="$(kubectl get -f "${resource_path}" -o "jsonpath={.kind}")"
  case "${kind}" in
    Rollout)
      echo "Waiting for rollout"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.metadata.labels['app\.kubernetes\.io/version']}=${new_tag}"
      echo "Rollout is at version: ${new_tag}"

      num_replicas="$(kubectl get -f "${resource_path}" -o "jsonpath={.spec.replicas}")"
      echo "Waiting for ${num_replicas} replicas"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.status.updatedReplicas}=${num_replicas}"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.status.readyReplicas}=${num_replicas}"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.status.availableReplicas}=${num_replicas}"
      echo "Rollout completed"
      return 0
      ;;

    Deployment)
      echo "Waiting for deployment"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.metadata.labels['app\.kubernetes\.io/version']}=${new_tag}"
      echo "Deployment is at version: ${new_tag}"

      num_replicas="$(kubectl get -f "${resource_path}" -o "jsonpath={.spec.replicas}")"
      echo "Waiting for ${num_replicas} replicas"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.status.updatedReplicas}=${num_replicas}"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.status.readyReplicas}=${num_replicas}"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.status.availableReplicas}=${num_replicas}"
      echo "Deployment completed"
      return 0
      ;;

    Service)
      echo "Skipping waiting for Service"
      return 0
      ;;

    AnalysisTemplate)
      echo "Skipping waiting for AnalysisTemplate"
      return 0
      ;;

    ServiceAccount)
      echo "Skipping waiting for ServiceAccount"
      return 0
      ;;

    RoleBinding)
      echo "Skipping waiting for RoleBinding"
      return 0
      ;;

    Role)
      echo "Skipping waiting for Role"
      return 0
      ;;

    ClusterRole)
      echo "Skipping waiting for ClusterRole"
      return 0
      ;;

    ClusterRoleBinding)
      echo "Skipping waiting for ClusterRoleBinding"
      return 0
      ;;

    *)
      echo "Unknown resource to wait for: ${kind}"
      return 1
      ;;
  esac

  echo "Unreachable. Case should handle any kind"
  return 1
}
