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

# The head commit sha
HEAD_SHA="$6"

# The output file to contain the id of the started GitHub Check
OUTPUT_FILE="$7"

echo "Deploying with parameters:"
echo "  APP_ID=${APP_ID}"
echo "  KEY_PATH=${KEY_PATH}"
echo "  REPO_SHORT=${REPO_SHORT}"
echo "  DETAILS_URL=${DETAILS_URL}"
echo "  EVENT_TYPE=${EVENT_TYPE}"
echo "  HEAD_SHA=${HEAD_SHA}"
echo "  OUTPUT_FILE=${OUTPUT_FILE}"

# Fetch GitHub Access Token
echo "Fetching GitHub Access Token"
GH_ACCESS_TOKEN="$(generate-installation-access-token "${APP_ID}" "${KEY_PATH}" "${REPO_SHORT}")"

echo "Starting GitHub Status Check"
STATUS_CHECK_DATA='{
  "name": "Jettison '"${EVENT_TYPE}"' Flow",
  "head_sha": "'"${HEAD_SHA}"'",
  "details_url": "'"${DETAILS_URL}"'",
  "status": "in_progress",
  "output":{
    "title": "Jettison '"${EVENT_TYPE}"' Flow for CI/CD",
    "summary": "Runs the '"${EVENT_TYPE}"' flow in an Argo workflow. See the [workflow link]('"${DETAILS_URL}"') for more details"
  }
}'

curl \
  --silent \
  --show-error \
  --fail \
  --location \
  --request POST \
  --header "Accept: application/vnd.github+json" \
  --header "Authorization: Bearer $GH_ACCESS_TOKEN" \
  --header "X-GitHub-Api-Version: 2022-11-28" \
  --data-binary "${STATUS_CHECK_DATA}" \
  "https://api.github.com/repos/${REPO_SHORT}/check-runs" \
  | jq -re '.id' \
  > "${OUTPUT_FILE}"
