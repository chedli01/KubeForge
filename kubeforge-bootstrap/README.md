# KubeForge — Day 1: Reproducible Kubernetes + Crossplane bootstrap

This starter kit targets **Windows 10/11 + Docker Desktop (Linux containers / WSL2) + Git Bash**.

## Architecture
- Kubernetes: kind, **1 control plane + 3 workers**, pinned `kindest/node:v1.34.0` image digest
- Helm: **v3.19.0**, installed locally into `.tools/bin` and SHA-256 verified
- Crossplane: Helm chart **v2.4.0**, installed in `crossplane-system`

## Prerequisites (installed beforehand)
- Docker Desktop with its engine running
- `kind` (preferably v0.30.0 for the pinned Kubernetes node image)
- `kubectl`
- Git Bash (which includes `curl`, `sha256sum`, `cygpath`)
- Windows PowerShell, used only to unzip the Helm Windows binary

Recommended: 8+ GB available for Docker/WSL; 12+ GB is more comfortable as ArgoCD and test workloads are added. Four kind nodes are **four Docker containers**, not four separate physical machines.

## Run each step (recommended for learning/debugging)
Open Git Bash at the repository root:

```bash
bash scripts/00-check-prerequisites.sh
bash scripts/01-create-cluster.sh
bash scripts/02-install-helm.sh
bash scripts/03-install-crossplane.sh
bash scripts/04-verify.sh
```

Or bootstrap everything with:

```bash
bash scripts/10-setup-all.sh
```

The scripts use the `kind-kubeforge` context explicitly to avoid changing unrelated clusters. You can re-run them; cluster creation is skipped if the cluster already exists, and `helm upgrade --install` is idempotent.

## Manual inspections

```bash
kubectl --context kind-kubeforge get nodes -o wide
kubectl --context kind-kubeforge get pods -n crossplane-system
kubectl --context kind-kubeforge get crd | grep crossplane
```

The local Helm executable lives at `.tools/bin/helm.exe`. To call it directly in Git Bash:

```bash
./.tools/bin/helm.exe ls -n crossplane-system --kube-context kind-kubeforge
```

## Cleanup (deletes the entire local lab)

```bash
bash scripts/99-destroy-cluster.sh
```

**Scope:** This is only the foundation. The XRD, Composition, Composition Function, ArgoCD and environment requests are deliberately **not** installed yet.

**Security:** Helm archives are checked against the official published SHA-256. Only the targeted `kind-kubeforge` cluster is modified. No Azure resources are created.

## Traceability

When running `bash scripts/10-setup-all.sh`, the entire console output is saved
under `logs/bootstrap-YYYYMMDD-HHMMSS.log` (ignored by Git). The version manifest,
cluster topology and provisioning scripts are intended to be committed to Git.
