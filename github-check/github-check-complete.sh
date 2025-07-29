#!/bin/bash
#
# Updates GitHub Check Runs
#
set -o errexit
set -o nounset
set -o pipefail


cd "$(dirname "$0")"
source ./generate-github-installation-access-token.sh


#
# Parameters
#

# GitHub App ID
APP_ID="$1"

# Path to the private key of the GitHub App
KEY_PATH="$2"

# The "org/name" portion of the repo url. e.g. "osoriano/deploy-steps"
REPO_SHORT="$3"

# Url to the Workflow UI
DETAILS_URL="$4"

# Event type. Used in the GitHub check description
EVENT_TYPE="$5"

# The ID of the check run to complete
CHECK_RUN_ID="$6"

# The completion status of the workflow
WORKFLOW_STATUS="$7"

echo "Deploying with parameters:"
echo "  APP_ID=${APP_ID}"
echo "  KEY_PATH=${KEY_PATH}"
echo "  REPO_SHORT=${REPO_SHORT}"
echo "  DETAILS_URL=${DETAILS_URL}"
echo "  EVENT_TYPE=${EVENT_TYPE}"
echo "  CHECK_RUN_ID=${CHECK_RUN_ID}"
echo "  WORKFLOW_STATUS=${WORKFLOW_STATUS}"

# Fetch GitHub Access Token
echo "Fetching GitHub Access Token"
GH_ACCESS_TOKEN="$(generate-installation-access-token "${APP_ID}" "${KEY_PATH}" "${REPO_SHORT}")"

# Get final status
echo "Determining final status"
case "${WORKFLOW_STATUS}" in
  Succeeded)
    CONCLUSION=success
    ;;

  Failed | Error)
    CONCLUSION=failure
    ;;

  *)
    echo "Unknown workflow status to handle: ${WORKFLOW_STATUS}"
    exit 1
    ;;
esac

echo "Completing GitHub Status Check"
STATUS_CHECK_DATA='{
  "conclusion": "'"${CONCLUSION}"'",
  "output": {
    "title": "Jettison '"${EVENT_TYPE}"' Flow for CI/CD",
    "summary": "The '"${EVENT_TYPE}"' flow completed with status **'"${WORKFLOW_STATUS}"'**. See the [Argo workflow link]('"${DETAILS_URL}"') for more details"
  }
}'

curl \
  --silent \
  --show-error \
  --fail \
  --location \
  --request PATCH \
  --header "Accept: application/vnd.github+json" \
  --header "Authorization: Bearer $GH_ACCESS_TOKEN" \
  --header "X-GitHub-Api-Version: 2022-11-28" \
  --data-binary "${STATUS_CHECK_DATA}" \
  "https://api.github.com/repos/${REPO_SHORT}/check-runs/${CHECK_RUN_ID}"
