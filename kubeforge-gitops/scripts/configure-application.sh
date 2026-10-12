#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_common.sh"
ensure_context
validate_repo_config

kubectl --context "$KUBE_CONTEXT" get crd applications.argoproj.io >/dev/null ||
  fail "Argo CD Application CRD not installed."
kubectl --context "$KUBE_CONTEXT" get crd devenvironments.platform.kubeforge.io >/dev/null ||
  fail "DevEnvironment CRD not registered (run platform setup first)."

render_template() {
  sed -e "s|__GIT_REPO_URL__|$GIT_REPO_URL|g" \
      -e "s|__GIT_REVISION__|$GIT_REVISION|g" \
      -e "s|__GIT_PATH__|$GIT_PATH|g" \
      -e "s|__APP_NAME__|$APP_NAME|g" "$1"
}

mkdir -p "$PROJECT_ROOT/.generated"

log "Configuring kubeforge AppProject..."
render_template "$PROJECT_ROOT/manifests/project.yaml.tpl" > "$PROJECT_ROOT/.generated/project.yaml"
kubectl --context "$KUBE_CONTEXT" apply -f "$PROJECT_ROOT/.generated/project.yaml"

log "Configuring Argo CD Application: $APP_NAME"
render_template "$PROJECT_ROOT/manifests/application.yaml.tpl" > "$PROJECT_ROOT/.generated/application.yaml"
kubectl --context "$KUBE_CONTEXT" apply -f "$PROJECT_ROOT/.generated/application.yaml"

log "Current Application:"
kubectl --context "$KUBE_CONTEXT" -n argocd get application "$APP_NAME"
