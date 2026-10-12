# Argo CD project limits this application to DevEnvironment XRs.
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: kubeforge
  namespace: argocd
spec:
  description: GitOps provisioning of KubeForge environments
  sourceRepos:
    - "__GIT_REPO_URL__"
  destinations:
    - server: https://kubernetes.default.svc
      namespace: "*"
  clusterResourceWhitelist:
    - group: platform.kubeforge.io
      kind: DevEnvironment
  namespaceResourceBlacklist:
    - group: "*"
      kind: "*"
