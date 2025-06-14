#!/bin/bash
#
# Clone the specified commit to prepare for a docker build.
# Adds a status file with "Skipped" if no relevant files changed.
#
set -o errexit
set -o nounset
set -o pipefail


#
# Parameters
#

# The repo clone url
REPO="$1"

# The path to clone the repo to
CLONE_PATH="$2"

# The revision id (e.g. commit sha hash)
REVISION_HASH="$3"

# The ref that will be used locally
REVISION_REF="$4"

# The path to the dockerfile to build
DOCKERFILE="$5"

# The path to the docker context used for the build"
DOCKER_CONTEXT_DIR="$6"

# The path to write the status to. The value is set to Skipped if no image
# build was performed and can be accessed if the execution was successful
STATUS_FILE="$7"

echo "$0 with parameters:"
echo "- REPO=${REPO}"
echo "- CLONE_PATH=${CLONE_PATH}"
echo "- REVISION_HASH=${REVISION_HASH}"
echo "- REVISION_REF=${REVISION_REF}"
echo "- DOCKERFILE=${DOCKERFILE}"
echo "- DOCKER_CONTEXT_DIR=${DOCKER_CONTEXT_DIR}"
echo "- STATUS_FILE=${STATUS_FILE}"

echo "Changing to clone path"
mkdir -p "${CLONE_PATH}"
cd "${CLONE_PATH}"

echo "Fetching and checking out changes"
git init
git remote add origin "${REPO}"
git fetch origin --depth 2 --no-tags "${REVISION_HASH}"
git reset --hard FETCH_HEAD

echo "Checking for relevant diffs"
if [[ -z "${DOCKER_CONTEXT_DIR}" ]]; then
  echo "Using empty docker context dir. Exiting early"
  exit 0
fi

CHANGED_FILES="$(mktemp "/tmp/$(basename "$0").XXXXXX")"
trap 'rm -f "${CHANGED_FILES}"' EXIT

echo "Changed files:"
git diff-tree --name-only --no-commit-id -r "${REVISION_HASH}" \
  | tee "${CHANGED_FILES}"

echo "Checking for diff in docker file"
if grep --fixed-strings --line-regexp "${DOCKERFILE}" "${CHANGED_FILES}"; then
  echo "Found changes in dockerfile. Exiting early"
  exit 0
fi

echo "Checking for diff in docker context dir"
TRAILING_SLASH="${DOCKER_CONTEXT_DIR: -1}"
if [[ "${TRAILING_SLASH}" != / ]]; then
  DOCKER_CONTEXT_DIR+=/
  echo "Added trailing slash to docker context dir: ${DOCKER_CONTEXT_DIR}"
fi

if cut -c "-${#DOCKER_CONTEXT_DIR}" "${CHANGED_FILES}" \
  | grep --fixed-strings --line-regexp "${DOCKER_CONTEXT_DIR}" "${CHANGED_FILES}"
then
  echo "Found changes in docker context dir. Exiting early"
  exit 0
fi

echo "Did not find relevant changes. Setting Skipped in status file"
echo "Skipped" > "${STATUS_FILE}"
