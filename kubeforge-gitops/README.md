# KubeForge — GitOps integration

Standalone Argo CD module for KubeForge. The other two folders remain unchanged:

```text
KubeForge/
├── kubeforge-bootstrap/       # kind, Helm, Crossplane installation
├── kubeforge-platform/        # DevEnvironment XRD, Composition, Function
└── kubeforge-gitops/          # THIS directory
    ├── config/gitops.env.example
    ├── manifests/project.yaml.tpl
    ├── manifests/application.yaml.tpl
    ├── environments/.gitkeep
    ├── environments/gitops-demo.yaml
    └── scripts/
        ├── _common.sh
        ├── install-argocd.sh
        ├── connect-private-repo.sh
        ├── configure-application.sh
        ├── verify-gitops.sh
        ├── open-dashboard.sh
        └── setup.sh
```

## Prerequisites

- Existing kind cluster and `kind-kubeforge` kubeconfig context; `kubectl` on PATH.
- Working Crossplane v2 installation and registered `DevEnvironment` CRD/Composition.
- GitHub repository and a `main` branch (or edit `GIT_REVISION`).
- Internet access for pulling the Argo CD installation manifests and images.
- The scripts are Bash-compatible with **Windows Git Bash**.
- Argo CD release is pinned to **v3.5.4**.

## Configure the repository

From **kubeforge-gitops/**:

```bash
cp config/gitops.env.example config/gitops.env
```

Edit `config/gitops.env` to set your actual `GIT_REPO_URL`, `GIT_REVISION` and `GIT_PATH`. `gitops.env` is intentionally ignored by Git.

**The relative Git path is critical:**

- If the *parent KubeForge/* directory is the Git repo root, leave `GIT_PATH=kubeforge-gitops/environments`.
- If *kubeforge-gitops/* itself is the Git repo root, set `GIT_PATH=environments`.

To inspect the repo root (when already inside a repo):

```bash
git rev-parse --show-toplevel
```

**Commit and push `environments/gitops-demo.yaml` to the configured GitHub branch before running the verification script.** Argo CD reads GitHub, not the files only on your desktop.

## Execute in order

From **kubeforge-gitops/**:

```bash
bash scripts/install-argocd.sh
# PRIVATE repository only (prompts for GitHub username + read-only PAT):
bash scripts/connect-private-repo.sh
bash scripts/configure-application.sh
bash scripts/verify-gitops.sh
```

Skip `connect-private-repo.sh` for a public repository. If private, prefer a **fine-grained GitHub personal access token with read-only Contents permission for this one repository**. Never commit credentials.

Once your Git repository and authentication are ready, `bash scripts/setup.sh` runs installation, Application creation, and verification in sequence (it does not register private repository credentials).

## What the module creates

1. Argo CD in the existing `kind-kubeforge` cluster (`argocd` namespace).
2. `AppProject/kubeforge`, permitting only the `platform.kubeforge.io/DevEnvironment` *cluster-scoped* resource type for application sync.
3. `Application/kubeforge-environments`, monitoring a single path in Git and applying those XR manifests.
4. Argo CD synchronization with `automated`, `prune`, `selfHeal`, `allowEmpty` enabled.

**Argo CD owns DevEnvironment XR declarations; Crossplane owns their child Namespace and ResourceQuota.**

## Test create / update / delete

- **Create:** GitHub already contains `environments/gitops-demo.yaml` (`small`). Run `bash scripts/verify-gitops.sh`. Confirm the `gitops-demo` namespace and ResourceQuota (2 CPU / 4Gi) exist.
- **Update:** Change `spec.size` to `medium`, commit and push. Watch the same ResourceQuota change to 4 CPU / 8Gi.
- **Delete:** Remove only `environments/gitops-demo.yaml` from Git, commit and push, then verify:

```bash
kubectl --context kind-kubeforge wait --for=delete devenvironment/gitops-demo --timeout=300s
kubectl --context kind-kubeforge wait --for=delete namespace/gitops-demo --timeout=300s
```

**DESTRUCTIVE WARNING:** With pruning enabled, removing an environment manifest from Git triggers deletion of the XR. Crossplane subsequently deletes the managed namespace, **including all workloads within it**. Only perform this with disposable test environments.

Keep `environments/.gitkeep` tracked so the Git directory exists when all YAML files are removed; `allowEmpty: true` allows Argo CD to prune the last XR.

## Dashboard

```bash
bash scripts/open-dashboard.sh
```

Open **https://localhost:8080** (self-signed certificate; browser may warn). User: `admin`; the script prints the initial password when still present. Stop the port-forward with Ctrl+C.

## Troubleshooting

```bash
kubectl --context kind-kubeforge -n argocd get applications
kubectl --context kind-kubeforge -n argocd describe application kubeforge-environments
kubectl --context kind-kubeforge -n argocd get pods
kubectl --context kind-kubeforge get devenvironments
kubectl --context kind-kubeforge describe devenvironment gitops-demo
```

If Argo CD reports `ComparisonError`, check the Git URL, repository credentials, branch, and path. If the XR exists but is not ready, inspect its Conditions and Crossplane logs.

## Technical references

- Official Argo CD installation: https://argo-cd.readthedocs.io/en/stable/getting_started/
- Official Argo CD GitOps sync policy: https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/

This package has been syntax-checked but **has not been run against your actual local Kubernetes cluster**.
