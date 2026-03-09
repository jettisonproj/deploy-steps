#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail


#
# Git push with retries.
#
# The retries may be needed in case other deploy steps are attempting to push
#
git-push-to-branch() {
  local base_branch
  base_branch="$1"
  local pr_branch
  pr_branch="$2"

  for (( i = 0 ; i < 5 ; i++ )); do
    if git push origin "HEAD:refs/heads/${pr_branch}"; then
      return 0
    fi
    sleep 2
    git fetch
    git rebase "origin/${base_branch}"
  done
  git push origin "HEAD:refs/heads/${pr_branch}"
}
