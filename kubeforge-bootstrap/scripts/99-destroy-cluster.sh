#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_common.sh"
require kind

if [[ "${1:-}" != '--yes' ]]; then
  printf "Delete the local kind cluster '%s' and ALL its workloads? [y/N] " "$KIND_CLUSTER_NAME"
  read -r response
  [[ "$response" == 'y' || "$response" == 'Y' ]] || { log 'Canceled.'; exit 0; }
fi

kind delete cluster --name "$KIND_CLUSTER_NAME"
log 'Cluster deleted. Locally installed Helm remains in .tools/bin.'
