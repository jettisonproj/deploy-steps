#!/bin/bash
#
# Create a new pr in a specified repo after substituting a string
# with a new value
#
set -o errexit
set -o nounset
set -o pipefail


cd "$(dirname "${0}")"
source ./generate-github-installation-access-token.sh
source ./git-push-to-branch.sh


#
# Parameters
#

# Url of the git repo to clone
REPO_URL="${1}"

# Repo short name. e.g. <repo-org>/<repo-name>
REPO_SHORT_NAME="${2}"

# Branch of the git repo to clone
REPO_BRANCH="${3}"

# GitHub App ID
APP_ID="${4}"

# GitHub App User ID
APP_USER_ID="${5}"

# GitHub App User Name
APP_USER_NAME="${6}"

# Path to the private key of the GitHub App
KEY_PATH="${7}"

# File path to apply the substituion to
FILE_PATHS="${8}"

# The registry of the image. Will be used as a prefix of the full image name
IMAGE_REGISTRY="${9}"

# The image repository prefix
IMAGE_REPO_PREFIX="${10}"

# The image tag
IMAGE_TAG="${11}"

# The image repository suffix
IMAGE_REPO_SUFFIX="${12}"

echo "Deploying with parameters:"
echo "  REPO_URL=${REPO_URL}"
echo "  REPO_SHORT_NAME=${REPO_SHORT_NAME}"
echo "  REPO_BRANCH=${REPO_BRANCH}"
echo "  APP_ID=${APP_ID}"
echo "  APP_USER_ID=${APP_USER_ID}"
echo "  APP_USER_NAME=${APP_USER_NAME}"
echo "  KEY_PATH=${KEY_PATH}"
echo "  FILE_PATHS=${FILE_PATHS}"
echo "  IMAGE_REGISTRY=${IMAGE_REGISTRY}"
echo "  IMAGE_REPO_PREFIX=${IMAGE_REPO_PREFIX}"
echo "  IMAGE_TAG=${IMAGE_TAG}"
echo "  IMAGE_REPO_SUFFIX=${IMAGE_REPO_SUFFIX}"

FULL_IMAGE_NAME="${IMAGE_REGISTRY}${IMAGE_REPO_PREFIX}${IMAGE_REPO_SUFFIX}:${IMAGE_TAG}"
PR_BRANCH="${IMAGE_REPO_PREFIX}${IMAGE_REPO_SUFFIX}-${IMAGE_TAG}"
echo "Derived parameters:"
echo "  FULL_IMAGE_NAME=${FULL_IMAGE_NAME}"

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
for FILE_PATH in ${FILE_PATHS}; do
  echo "Substituting image version for: ${FILE_PATH}"
  sed --regexp-extended "s|${IMAGE_REGISTRY}${IMAGE_REPO_PREFIX}${IMAGE_REPO_SUFFIX}:[a-zA-Z0-9_.-]+|${FULL_IMAGE_NAME}|g" -i "${FILE_PATH}"
done

# Commit to git
echo "Pushing to git"
if git diff --quiet; then
  echo "No changes to commit"
  echo "Exiting early"
  exit 0
fi

PR_TITLE="Bump \`${IMAGE_REPO_PREFIX}${IMAGE_REPO_SUFFIX}\` to \`${IMAGE_TAG:0:8}\`"
PR_BODY="Bump \`${IMAGE_REPO_PREFIX}${IMAGE_REPO_SUFFIX}\` to version:
${IMAGE_TAG}"

git commit -am "${PR_TITLE}

${PR_BODY}"

# Push to a branch
NEW_REPO_URL="${REPO_URL/github.com/${APP_USER_NAME}:${GH_ACCESS_TOKEN}@github.com}"
git remote set-url origin "${NEW_REPO_URL}"
git-push-to-branch "${REPO_BRANCH}" "${PR_BRANCH}"

# Create a PR
PULL_REQUEST_DATA='{
  "title": "'"${PR_TITLE}"'",
  "body": "'"${PR_BODY//$'\n'/\\n}"'",
  "head": "'"${PR_BRANCH}"'",
  "base": "'"${REPO_BRANCH}"'"
}'

curl \
  --silent \
  --show-error \
  --fail \
  --location \
  --header "Accept: application/vnd.github+json" \
  --header "Authorization: Bearer $GH_ACCESS_TOKEN" \
  --header "X-GitHub-Api-Version: 2022-11-28" \
  --data-binary "${PULL_REQUEST_DATA}"  \
  "https://api.github.com/repos/${REPO_SHORT_NAME}/pulls"
