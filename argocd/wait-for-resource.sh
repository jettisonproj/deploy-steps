#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail


#
# Wait for a Rollout to finish the update that was just synced
#
# The status is only trusted once the controller has observed the current
# generation (status.observedGeneration >= metadata.generation). Before that,
# status still describes the previous revision, so a rollout that is aborted
# moments later could otherwise be reported as successful.
#
# Returns 1 if the rollout is aborted or degraded, 0 once it has completed.
#
wait-for-rollout-completed() {
  local resource_path="$1"
  local status_line=""
  local generation observed_generation phase abort updated ready available desired completed

  local jsonpath='{.metadata.generation}|{.status.observedGeneration}|{.status.phase}|{.status.abort}|{.status.updatedReplicas}|{.status.readyReplicas}|{.status.availableReplicas}|{.spec.replicas}|{.status.conditions[?(@.type=="Completed")].status}'

  while true; do
    if ! status_line="$(kubectl get -f "${resource_path}" --allow-missing-template-keys=true -o "jsonpath=${jsonpath}")"; then
      warn "Failed to get rollout status. Retrying"
      sleep 5
      continue
    fi

    IFS='|' read -r generation observed_generation phase abort updated ready available desired completed <<< "${status_line}"
    generation="${generation:-0}"
    observed_generation="${observed_generation:-0}"
    updated="${updated:-0}"
    ready="${ready:-0}"
    available="${available:-0}"
    desired="${desired:-1}"

    if (( observed_generation < generation )); then
      info "Waiting for controller to observe generation ${generation} (observed ${observed_generation})"
    elif [[ "${abort}" == true || "${phase}" == Degraded ]]; then
      error "Rollout is degraded or aborted: phase=${phase} abort=${abort}"
      return 1
    elif [[ "${phase}" == Healthy && "${completed}" == True ]] \
      && (( updated == desired && ready == desired && available == desired )); then
      return 0
    else
      info "Waiting for rollout: phase=${phase} updated=${updated}/${desired} ready=${ready}/${desired} available=${available}/${desired}"
    fi

    sleep 5
  done
}

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
      info "Waiting for rollout"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.metadata.labels['app\.kubernetes\.io/version']}=${new_tag}"
      info "Rollout is at version: ${new_tag}"

      wait-for-rollout-completed "${resource_path}" || return 1
      info "Rollout completed"
      return 0
      ;;

    Deployment)
      info "Waiting for deployment"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.metadata.labels['app\.kubernetes\.io/version']}=${new_tag}"
      info "Deployment is at version: ${new_tag}"

      num_replicas="$(kubectl get -f "${resource_path}" -o "jsonpath={.spec.replicas}")"
      info "Waiting for ${num_replicas} replicas"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.status.updatedReplicas}=${num_replicas}"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.status.readyReplicas}=${num_replicas}"
      kubectl wait -f "${resource_path}" --timeout=-1s --for=jsonpath="{.status.availableReplicas}=${num_replicas}"
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
