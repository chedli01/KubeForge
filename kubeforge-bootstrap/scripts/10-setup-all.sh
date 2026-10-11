#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
mkdir -p "$PROJECT_ROOT/logs"
LOG_FILE="$PROJECT_ROOT/logs/bootstrap-$(date +%Y%m%d-%H%M%S).log"
printf '[KubeForge] Session log: %s\n' "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1
for step in \
  00-check-prerequisites.sh \
  01-create-cluster.sh \
  02-install-helm.sh \
  03-install-crossplane.sh \
  04-verify.sh; do
  bash "$SCRIPTS_DIR/$step"
done
