# Provenance

This file records where every file under `upstream/` came from, so a reviewer can verify the copy and its license.

Copy date: 2026-11-19.

## Sources

| Directory | Source repository | Ref | Commit | License |
|---|---|---|---|---|
| `upstream/starrocks/` | https://github.com/StarRocks/starrocks | `branch-4.1` | `e355a3595ec52bca1ac667ff80cd772087082613` | Apache-2.0 |
| `upstream/starrocks-kubernetes-operator/` | https://github.com/StarRocks/starrocks-kubernetes-operator | `main` | `f6b2c1fe8d110b00d1f79f06cc90a3a4d84eaea0` | Apache-2.0 |
| `upstream/data-on-eks/` | https://github.com/awslabs/data-on-eks | `main` | `4e643331cfde2b9f5341df92fbc036cdb85fbedb` | Apache-2.0 |

All files under `upstream/` are byte-for-byte copies. Nothing was edited.

## What was copied

### StarRocks

| Upstream path | Copied to |
|---|---|
| `docs/en/` (entire tree) | `upstream/starrocks/docs/en/` |
| `LICENSE.txt` | `upstream/starrocks/LICENSE.txt` |
| `NOTICE.txt` | `upstream/starrocks/NOTICE.txt` |

File types in `docs/en/`: Markdown (`.md`, `.mdx`), Docusaurus category files (`.yml`), and images (`.png`, `.jpeg`) under `_assets/`.

### StarRocks Kubernetes Operator

| Upstream path | Copied to | Contents |
|---|---|---|
| `doc/` | `upstream/starrocks-kubernetes-operator/doc/` | How-to guides and the API reference |
| `examples/` | `upstream/starrocks-kubernetes-operator/examples/` | Example `StarRocksCluster` manifests |
| `deploy/` | `upstream/starrocks-kubernetes-operator/deploy/` | Operator manifest and the two CRDs |
| `helm-charts/**/values.yaml`, `Chart.yaml`, `README.md`, `LICENSE` | same relative path | Chart metadata, documentation and default values |
| `README.md`, `README_ZH-CN.md`, `CHANGELOG.md`, `LICENSE` | `upstream/starrocks-kubernetes-operator/` | Top-level documentation |

### Data on EKS

| Upstream path | Contents |
|---|---|
| `website/docs/datastacks/databases/starrocks-on-eks/` | Stack overview, infrastructure guide, TPC-DS benchmark guide |
| `website/docs/benchmarks/starrocks-benchmark.md` | Benchmark write-up |
| `data-stacks/starrocks-on-eks/examples/starrocks-shared-data.yaml` | Shared-data cluster manifest |
| `data-stacks/starrocks-on-eks/examples/starrocks-shared-nothing.yaml` | Shared-nothing cluster manifest |
| `infra/terraform/manifests/starrocks/` | KEDA ScaledObject, PodMonitors, StorageClass |
| `infra/terraform/helm-values/starrocks-operator.yaml` | Operator Helm values used by the stack |
| `infra/terraform/argocd-applications/starrocks-operator.yaml` | Argo CD Application for the operator |
| `LICENSE`, `NOTICE` | License and notice |

All paths are kept relative to the upstream repository root, under `upstream/data-on-eks/`.

## What was deliberately left out

| Excluded | Why |
|---|---|
| All program source code (Go, Java, C++, Python) | This is a documentation repository |
| `vendor/` in the operator repository | Vendored third-party Go modules under their own licenses |
| `thirdparty/`, `licenses/`, `licenses-binary/` in the StarRocks repository | Relate to bundled third-party software that is not included here |
| Helm chart `templates/` | Go templates, treated as code |
| Terraform (`.tf`, `.tfvars`), shell scripts, Dockerfiles | Code. The guides describe what the Data on EKS Terraform does instead |
| Data on EKS TPC-DS job manifests and SQL, the `agentic-analytics` example | Benchmark tooling and application code |
| `docs/zh/`, `docs/ja/` in the StarRocks repository | Non-English translations |
| `docs/docusaurus/` and other site tooling | Website build code |

## Notes for license reviewers

- The only license in this repository is Apache-2.0. No copyleft-licensed files are included.
- The upstream `LICENSE` and `NOTICE` files are preserved next to the content they cover.
- `upstream/starrocks/docs/en/benchmarking/` contains the text of SSB, TPC-H and TPC-DS benchmark queries as published in the StarRocks documentation. If your organization treats TPC benchmark material separately, that folder can be removed without affecting anything else.
- Example manifests reference container images such as `starrocks/fe-ubuntu`. No images are included. Image licensing is a separate review.

## How to verify the copy

```bash
# StarRocks docs
git clone --depth 1 --filter=blob:none --sparse -b branch-4.1 https://github.com/StarRocks/starrocks.git
cd starrocks && git sparse-checkout set docs/en && git checkout e355a3595ec52bca1ac667ff80cd772087082613
diff -r docs/en /path/to/this/repo/upstream/starrocks/docs/en

# Operator
git clone https://github.com/StarRocks/starrocks-kubernetes-operator.git
cd starrocks-kubernetes-operator && git checkout f6b2c1fe8d110b00d1f79f06cc90a3a4d84eaea0
diff -r doc /path/to/this/repo/upstream/starrocks-kubernetes-operator/doc
```

If the branch has moved past the recorded commit, fetch with enough depth to reach it before checking out.

## Derived file

`guides/reference/crd-api-reference.md` is a mechanical conversion of `upstream/starrocks-kubernetes-operator/doc/api.md` from HTML to Markdown tables. Field names, types and descriptions are unchanged.
