#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail


debug() {
  printf "\033[32mDBUG\033[0m "
  echo "$@"
}

info() {
  printf "\033[34mINFO\033[0m "
  echo "$@"
}

warn() {
  printf "\033[33mWARN\033[0m "
  echo "$@"
}

error() {
  printf "\033[31mEROR\033[0m "
  echo "$@"
}
