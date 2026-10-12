#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_common.sh"
validate_repo_config
log "Before continuing: GitHub branch '$GIT_REVISION' must already contain '$GIT_PATH/$TEST_ENV.yaml'."
log "For private repos, register credentials with scripts/connect-private-repo.sh before running setup."
bash "$PROJECT_ROOT/scripts/install-argocd.sh"
bash "$PROJECT_ROOT/scripts/configure-application.sh"
bash "$PROJECT_ROOT/scripts/verify-gitops.sh"
