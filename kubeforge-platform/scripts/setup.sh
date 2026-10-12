#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_common.sh"
require tee
mkdir -p "$PROJECT_ROOT/logs"
LOGFILE="$PROJECT_ROOT/logs/platform-setup-$(date +%Y%m%d-%H%M%S).log"
log "Saving setup output to $LOGFILE"
{
  bash "$PROJECT_ROOT/scripts/register-api.sh"
  bash "$PROJECT_ROOT/scripts/install-function.sh"
  bash "$PROJECT_ROOT/scripts/apply-composition.sh"
  bash "$PROJECT_ROOT/scripts/create-environment.sh"
  bash "$PROJECT_ROOT/scripts/verify-environment.sh"
} 2>&1 | tee "$LOGFILE"
