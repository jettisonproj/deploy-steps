#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail


#
# Wait for the resource to be available
#
# NOTE: Ensure the client (e.g. deploy-step-executor) has read access
# to these resources (namespaced and cluster resources)
#
wait-for-resource() {
  local resource_path="$1"
  local new_tag="$2"

  kind="$(kubectl get -f "${resource_path}" -o "jsonpath={.kind}")"
  case "${kind}" in
    Rollout)
      info "Waiting for rollout version: ${new_tag}"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.metadata.labels['app\.kubernetes\.io/version']}=${new_tag}"
      info "Rollout is at version: ${new_tag}"

      generation="$(kubectl get -f "${resource_path}" -o "jsonpath={.metadata.generation}")"
      info "Waiting for rollout generation: ${generation}"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.status.observedGeneration}=${generation}"
      info "Rollout is at generation ${generation}"

      num_replicas="$(kubectl get -f "${resource_path}" -o "jsonpath={.spec.replicas}")"
      info "Waiting for ${num_replicas} replicas"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.status.updatedReplicas}=${num_replicas}"
      info "Rollout replicas are updated"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.status.readyReplicas}=${num_replicas}"
      info "Rollout replicas are ready"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.status.availableReplicas}=${num_replicas}"
      info "Rollout replicas are available"

      info "Waiting for rollout to be Healthy"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.status.phase}=Healthy"
      info "Rollout is Healthy"

      info "Rollout completed"
      return 0
      ;;

    Deployment)
      info "Waiting for deployment version: ${new_tag}"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.metadata.labels['app\.kubernetes\.io/version']}=${new_tag}"
      info "Deployment is at version: ${new_tag}"

      generation="$(kubectl get -f "${resource_path}" -o "jsonpath={.metadata.generation}")"
      info "Waiting for deployment generation: ${generation}"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.status.observedGeneration}=${generation}"
      info "Deployment is at generation: ${generation}"

      info "Waiting for ${num_replicas} replicas"
      num_replicas="$(kubectl get -f "${resource_path}" -o "jsonpath={.spec.replicas}")"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.status.updatedReplicas}=${num_replicas}"
      info "Deployment replicas are updated"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.status.readyReplicas}=${num_replicas}"
      info "Deployment replicas are ready"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.status.availableReplicas}=${num_replicas}"
      info "Deployment replicas are available"

      info "Deployment completed"
      return 0
      ;;

    Service)
      info "Skipping waiting for Service"
      return 0
      ;;

    AnalysisTemplate)
      info "Skipping waiting for AnalysisTemplate"
      return 0
      ;;

    ServiceAccount)
      info "Skipping waiting for ServiceAccount"
      return 0
      ;;

    RoleBinding)
      info "Skipping waiting for RoleBinding"
      return 0
      ;;

    Role)
      info "Skipping waiting for Role"
      return 0
      ;;

    ClusterRole)
      info "Skipping waiting for ClusterRole"
      return 0
      ;;

    ClusterRoleBinding)
      info "Skipping waiting for ClusterRoleBinding"
      return 0
      ;;

    HTTPRoute)
      info "Skipping waiting for HTTPRoute"
      return 0
      ;;

    *)
      error "Unknown resource to wait for: ${kind}"
      return 1
      ;;
  esac

  error "Unreachable. Case should handle any kind"
  return 1
}
