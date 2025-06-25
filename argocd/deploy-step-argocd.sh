#!/bin/bash
#
# Update a Kubernetes resource by pushing to a git repo.
# ArgoCD is expected to synchronize with the git repo.
#
# Then, this script will wait for the deployment to complete
#
set -o errexit
set -o nounset
set -o pipefail


cd "$(dirname "${0}")"
source ./generate-github-installation-access-token.sh
source ./wait-for-resource.sh
source ./git-push.sh


#
# Parameters
#

# Url of the git repo to clone
REPO_URL="${1}"

# Branch of the git repo to clone
REPO_BRANCH="${2}"

# GitHub App ID
APP_ID="${3}"

# GitHub App User ID
APP_USER_ID="${4}"

# GitHub App User Name
APP_USER_NAME="${5}"

# Path to the private key of the GitHub App
KEY_PATH="${6}"

# Path to the resource inside the repo. If a directory, runs all on files in directory
RESOURCE_PATH="${7}"

# The registry of the image. Will be used as a prefix of the full image name
IMAGE_REGISTRY="${8}"

# The image repository prefix
IMAGE_REPO_PREFIX="${9}"

# The image tag
IMAGE_TAG="${10}"

# The image repository suffix
IMAGE_REPO_SUFFIX="${11}"

echo "Deploying with parameters:"
echo "  REPO_URL=${REPO_URL}"
echo "  REPO_BRANCH=${REPO_BRANCH}"
echo "  APP_ID=${APP_ID}"
echo "  APP_USER_ID=${APP_USER_ID}"
echo "  APP_USER_NAME=${APP_USER_NAME}"
echo "  KEY_PATH=${KEY_PATH}"
echo "  RESOURCE_PATH=${RESOURCE_PATH}"
echo "  IMAGE_REGISTRY=${IMAGE_REGISTRY}"
echo "  IMAGE_REPO_PREFIX=${IMAGE_REPO_PREFIX}"
echo "  IMAGE_TAG=${IMAGE_TAG}"
echo "  IMAGE_REPO_SUFFIX=${IMAGE_REPO_SUFFIX}"

FULL_IMAGE_NAME="${IMAGE_REGISTRY}${IMAGE_REPO_PREFIX}${IMAGE_REPO_SUFFIX}:${IMAGE_TAG}"
FULL_TEST_IMAGE_NAME="${IMAGE_REGISTRY}${IMAGE_REPO_PREFIX}${IMAGE_REPO_SUFFIX}-integration-test:${IMAGE_TAG}"
echo "Derived parameters:"
echo "  FULL_IMAGE_NAME=${FULL_IMAGE_NAME}"
echo "  FULL_TEST_IMAGE_NAME=${FULL_TEST_IMAGE_NAME}"

# Clone the repo
echo "Cloning the repo"
git clone --depth 1 --branch "${REPO_BRANCH}" --single-branch "${REPO_URL}" /repo
cd /repo

# Configure git
echo "Configuring git"
git config user.name "${APP_USER_NAME}"
git config user.email "${APP_USER_ID}+${APP_USER_NAME}@users.noreply.github.com"
GH_ACCESS_TOKEN="$(generate-installation-access-token "${APP_ID}" "${KEY_PATH}" "${IMAGE_REPO_PREFIX}")"
git config user.password "${GH_ACCESS_TOKEN}"

# Perform the subtitution
echo "Substituting image version"
if [[ -d "${RESOURCE_PATH}" ]]; then
  for resource_path_part in "${RESOURCE_PATH}"/*; do
    if [[ -f "${resource_path_part}" ]]; then
      file_ext=${resource_path_part##*.}
      if [[ "${file_ext}" == yaml || "${file_ext}" == yml || "${file_ext}" == json ]]; then
        echo "Substituting image version for: ${resource_path_part}"
        sed --regexp-extended "s|${IMAGE_REGISTRY}${IMAGE_REPO_PREFIX}${IMAGE_REPO_SUFFIX}:[a-zA-Z0-9_.-]+|${FULL_IMAGE_NAME}|g" -i "${resource_path_part}"
        sed --regexp-extended "s|${IMAGE_REGISTRY}${IMAGE_REPO_PREFIX}${IMAGE_REPO_SUFFIX}-integration-test:[a-zA-Z0-9_.-]+|${FULL_TEST_IMAGE_NAME}|g" -i "${resource_path_part}"
        sed --regexp-extended "s|(app\\.kubernetes\\.io/version[\": ]+)[a-zA-Z0-9_.-]+|\\1${IMAGE_TAG}|g" -i "${resource_path_part}"
      else
        echo "Warning: unknown file extension ${file_ext}"
      fi
    else
      # This may need an update if traversing the directory is needed
      echo "Warning: skipping non-file: ${resource_path_part}"
    fi
  done
elif [[ -f "${RESOURCE_PATH}" ]]; then
  echo "Substituting image version for: ${RESOURCE_PATH}"
  sed --regexp-extended "s|${IMAGE_REGISTRY}${IMAGE_REPO_PREFIX}${IMAGE_REPO_SUFFIX}:[a-zA-Z0-9_.-]+|${FULL_IMAGE_NAME}|g" -i "${RESOURCE_PATH}"
  sed --regexp-extended "s|${IMAGE_REGISTRY}${IMAGE_REPO_PREFIX}${IMAGE_REPO_SUFFIX}-integration-test:[a-zA-Z0-9_.-]+|${FULL_TEST_IMAGE_NAME}|g" -i "${RESOURCE_PATH}"
  sed --regexp-extended "s|(app\\.kubernetes\\.io/version[\": ]+)[a-zA-Z0-9_.-]+|\\1${IMAGE_TAG}|g" -i "${RESOURCE_PATH}"
else
  echo "Resource path does not exist: ${RESOURCE_PATH}"
  exit 1
fi

# Commit and push to git
echo "Pushing to git"
if git diff --quiet; then
  echo "No changes to commit"
  echo "Exiting early"
  exit 0
fi
git commit -am "Bump ${RESOURCE_PATH} to \`${IMAGE_TAG:0:8}\`

Bump resource ${RESOURCE_PATH} to version:
${IMAGE_TAG}"

NEW_REPO_URL="${REPO_URL/github.com/${APP_USER_NAME}:${GH_ACCESS_TOKEN}@github.com}"
git remote set-url origin "${NEW_REPO_URL}"
git-push "${REPO_BRANCH}"

# Wait for the resource to be available
echo "Waiting for resources"
if [[ -d "${RESOURCE_PATH}" ]]; then
  for resource_path_part in "${RESOURCE_PATH}"/*; do
    if [[ -f "${resource_path_part}" ]]; then
      file_ext=${resource_path_part##*.}
      if [[ "${file_ext}" == yaml || "${file_ext}" == yml || "${file_ext}" == json ]]; then
        echo "Waiting for resource: ${resource_path_part}"
        wait-for-resource "${resource_path_part}" "${IMAGE_TAG}"
      else
        echo "Warning: unknown file extension ${file_ext}"
      fi
    else
      # This may need an update if traversing the directory is needed
      echo "Warning: skipping non-file: ${resource_path_part}"
    fi
  done
elif [[ -f "${RESOURCE_PATH}" ]]; then
  echo "Waiting for resource: ${RESOURCE_PATH}"
  wait-for-resource "${RESOURCE_PATH}" "${IMAGE_TAG}"
else
  echo "Resource path does not exist: ${RESOURCE_PATH}"
  exit 1
fi
