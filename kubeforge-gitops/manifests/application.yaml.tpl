# Only DevEnvironment request YAMLs in the configured Git path are managed.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: __APP_NAME__
  namespace: argocd
spec:
  project: kubeforge
  source:
    repoURL: "__GIT_REPO_URL__"
    targetRevision: "__GIT_REVISION__"
    path: "__GIT_PATH__"
    directory:
      recurse: false
      include: "*.yaml"
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      enabled: true
      prune: true
      selfHeal: true
      allowEmpty: true
    syncOptions:
      - ServerSideApply=true
