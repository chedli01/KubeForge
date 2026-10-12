# KubeForge Platform — self-service Kubernetes environments

This directory contains the Kubernetes platform APIs and reconciled resource templates for KubeForge. It is **independent of `kubeforge-bootstrap`**. The bootstrap folder installs the local kind cluster, Helm, and Crossplane; this folder defines **what Crossplane should manage**.

## Recommended project layout

```text
KubeForge/
├── kubeforge-bootstrap/          # Existing cluster setup and dependencies
└── kubeforge-platform/           # This folder: platform API and resources
    ├── config/cluster.env        # One kubeconfig context setting
    ├── manifests/
    │   ├── xrds/                 # Defines DevEnvironment API schema
    │   ├── functions/            # Installs Go-templating function
    │   ├── rbac/                 # Crossplane permissions for native resources
    │   └── compositions/         # Recipe for Namespace + ResourceQuota
    ├── examples/                 # Environment request YAMLs
    ├── scripts/                  # Independent installation and verification
    └── README.md
```

No files need to be copied into `kubeforge-bootstrap/`, and its existing scripts do not need to change.

## Prerequisites

- Existing cluster `kind-kubeforge` with Crossplane v2.4.0 healthy (created by `kubeforge-bootstrap`).
- `kubectl` working in Git Bash with kubeconfig context `kind-kubeforge`.
- Registry connectivity to download the Composition Function package.

`config/cluster.env` is the **single source of truth** for the target kubeconfig context used by all scripts in this folder. `_common.sh` sources it and provides `log`, `fail`, `require` and safety checks, without depending on the bootstrap scripts.

## Apply step-by-step

From `kubeforge-platform/`:

```bash
bash scripts/register-api.sh
bash scripts/install-function.sh
bash scripts/apply-composition.sh
bash scripts/create-environment.sh
bash scripts/verify-environment.sh
```

Or run the full sequence with one command (and save a log under `logs/`):

```bash
bash scripts/setup.sh
```

All scripts explicitly use `--context "$KUBE_CONTEXT"`; they do not change your `kubectl` default context.

## What should be created?

- Kubernetes CRD `devenvironments.platform.kubeforge.io` generated from our Crossplane XRD.
- Crossplane `Function/function-go-templating` and `Composition/kubeforge-devenvironment`.
- RBAC ClusterRole aggregated into Crossplane's permissions.
- `DevEnvironment/payments-dev` -> `Namespace/payments-dev` and `ResourceQuota/environment-quota` in that namespace, configured for `requests.cpu=2` and `requests.memory=4Gi`.

Inspect:

```bash
kubectl --context kind-kubeforge get devenvironments
kubectl --context kind-kubeforge get ns payments-dev
kubectl --context kind-kubeforge -n payments-dev describe resourcequota environment-quota
```

## Test an update

```bash
kubectl --context kind-kubeforge apply -f examples/payments-medium.yaml
kubectl --context kind-kubeforge -n payments-dev describe resourcequota environment-quota
```

Expected updated quota: 4 CPU requests / 8Gi memory requests. To revert:

```bash
kubectl --context kind-kubeforge apply -f examples/payments-dev.yaml
```

## Troubleshooting

```bash
kubectl --context kind-kubeforge describe devenvironment payments-dev
kubectl --context kind-kubeforge get composition kubeforge-devenvironment -o yaml
kubectl --context kind-kubeforge -n crossplane-system logs deployment/crossplane --tail=100
kubectl --context kind-kubeforge get functions.pkg.crossplane.io
kubectl --context kind-kubeforge auth can-i create resourcequotas --as=system:serviceaccount:crossplane-system:crossplane --all-namespaces
```

Keep the cluster if a stage fails; inspect the logs and resource events. **Do not delete the XRD to troubleshoot**: removing it can affect custom resource instances and their composed resources.

## Optional cleanup of the sample

```bash
kubectl --context kind-kubeforge delete -f examples/payments-dev.yaml
```

**Warning:** Deleting the sample environment may also delete its namespace and workloads inside it. Do not use against a namespace holding valuable data.

## Implementation notes

This first iteration uses Crossplane v2 native Kubernetes composition (no provider-kubernetes). Our XRD uses `scope: Cluster` because the Composition owns a cluster-scoped Namespace. Network isolation, developer RBAC, ServiceAccounts and LimitRange come later; this MVP deliberately provisions only a Namespace and ResourceQuota. The first template marks resources ready once observed; the verification script additionally asserts actual quota values.
