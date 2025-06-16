#!/bin/bash
#
# Clone the specified PR to prepare for a docker build
#
# Additionally:
# - Adds a status file with "Skipped" if no relevant files changed
# - Adds override files to the clone directory after cloning
#
set -o errexit
set -o nounset
set -o pipefail


#
# Parameters
#

# The repo clone url
REPO="${1}"

# The path to clone the repo to
CLONE_PATH="${2}"

# The PR revision id (e.g. commit sha hash)
PR_REVISION_HASH="${3}"

# The PR ref that will be used locally
PR_REVISION_REF="${4}"

# The base ref revision id (e.g. commit sha hash)
BASE_REVISION_HASH="${5}"

# The base ref that will be used locally
BASE_REVISION_REF="${6}"

# The path to the dockerfile to build
DOCKERFILE="${7}"

# The path to the docker context used for the build"
DOCKER_CONTEXT_DIR="${8}"

# The path to write the status to. The value is set to Skipped if no image
# build was performed and can be accessed if the execution was successful
STATUS_FILE="${9}"

# After cloning, add the override files from this directory
# to the clone directory
REPO_OVERRIDE_DIR="${10}"

echo "$0 with parameters:"
echo "- REPO=${REPO}"
echo "- CLONE_PATH=${CLONE_PATH}"
echo "- PR_REVISION_HASH=${PR_REVISION_HASH}"
echo "- PR_REVISION_REF=${PR_REVISION_REF}"
echo "- BASE_REVISION_HASH=${BASE_REVISION_HASH}"
echo "- BASE_REVISION_REF=${BASE_REVISION_REF}"
echo "- DOCKERFILE=${DOCKERFILE}"
echo "- DOCKER_CONTEXT_DIR=${DOCKER_CONTEXT_DIR}"
echo "- STATUS_FILE=${STATUS_FILE}"
echo "- REPO_OVERRIDE_DIR=${REPO_OVERRIDE_DIR}"

echo "Changing to clone path"
mkdir -p "${CLONE_PATH}"
cd "${CLONE_PATH}"

echo "Fetching and checking out changes"
git init
git remote add origin "${REPO}"
git fetch origin --depth 1 --no-tags "${BASE_REVISION_HASH}"
git fetch origin --no-tags "${PR_REVISION_HASH}"
git reset --hard FETCH_HEAD

# Copies the files mounted into the REPO_OVERRIDE_DIR
# to the clone dir
copy_override_files() {
  echo "Adding files from override dir to clone dir"

  if [[ ! -d "${REPO_OVERRIDE_DIR}" ]]; then
    echo "Skipping override files. No override dir exists"
    return 0
  fi

  find "${REPO_OVERRIDE_DIR}" -type f -print0 | while IFS= read -r -d $'\0' repo_override_file; do
    relative_override_file="${repo_override_file:${#REPO_OVERRIDE_DIR}}"
    clone_override_file="${CLONE_PATH}${relative_override_file}"

    relative_override_dir="$(dirname "${relative_override_file}")"
    clone_override_dir="${CLONE_PATH}${relative_override_dir}"

    echo "${repo_override_file} -> ${clone_override_file}"

    mkdir -p "${clone_override_dir}"
    cp "${repo_override_file}" "${clone_override_file}"

  done

  echo "Finished adding override files"
}

echo "Checking for relevant diffs"
if [[ -z "${DOCKER_CONTEXT_DIR}" ]]; then
  echo "Using empty docker context dir"
  copy_override_files
  echo "Succeeded" > "${STATUS_FILE}"
  exit 0
fi

CHANGED_FILES="$(mktemp "/tmp/$(basename "$0").XXXXXX")"
trap 'rm -f "${CHANGED_FILES}"' EXIT

echo "Changed files:"
git diff --name-only "${BASE_REVISION_HASH}" "${PR_REVISION_HASH}" \
  | tee "${CHANGED_FILES}"


echo "Checking for diff in docker file"
if grep --fixed-strings --line-regexp "${DOCKERFILE}" "${CHANGED_FILES}"; then
  echo "Found changes in dockerfile"
  copy_override_files
  echo "Succeeded" > "${STATUS_FILE}"
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
  echo "Found changes in docker context dir"
  copy_override_files
  echo "Succeeded" > "${STATUS_FILE}"
  exit 0
fi

echo "Did not find relevant changes. Setting Skipped in status file"
echo "Skipped" > "${STATUS_FILE}"
