# StarRocks on Kubernetes: documentation

A documentation-only repository for running [StarRocks](https://github.com/StarRocks/starrocks) on Kubernetes with the [StarRocks Kubernetes Operator](https://github.com/StarRocks/starrocks-kubernetes-operator).

It contains two things:

1. **Original guides** in [`guides/`](guides/README.md). These are task-oriented and cover install, configuration, storage, scaling, security, data lake access, observability, upgrades, disaster recovery, EKS, and troubleshooting.
2. **Unmodified upstream documentation** in [`upstream/`](upstream/). This is the English StarRocks documentation, the operator documentation with its example manifests and Helm values, and the StarRocks-on-EKS documentation from AWS Data on EKS.

There is no source code here. No Go, Java, C++, Python, Terraform, shell scripts, Helm templates, or vendored dependencies. See [PROVENANCE.md](PROVENANCE.md) for exactly what was copied, from which commit, and what was left out.

## Start here

| If you want to | Read |
|---|---|
| Understand the moving parts | [Architecture](guides/01-architecture.md) |
| Install the operator | [Install the operator](guides/02-install-operator.md) |
| Stand up a cluster | [Deploy a cluster](guides/03-deploy-cluster.md) |
| Look up a CR field | [The StarRocksCluster resource](guides/04-starrockscluster-resource.md) and the [CRD API reference](guides/reference/crd-api-reference.md) |
| Look up a Helm value | [Helm values reference](guides/reference/helm-values-reference.md) |
| Query an S3 data lake through AWS Glue | [Data lake on S3 and Glue](guides/10-data-lake-on-s3-and-glue.md) |
| Run it on Amazon EKS | [EKS reference](guides/15-eks-reference.md) |
| Fix something | [Troubleshooting](guides/16-troubleshooting.md) |
| Find the upstream page for a topic | [Upstream documentation map](guides/17-upstream-doc-map.md) |

The full list of guides is in [`guides/README.md`](guides/README.md).

## Layout

```
.
├── guides/                               Original guides (written for this repository)
│   ├── 01-architecture.md ... 18-ai-agents-and-mcp.md
│   ├── examples/                         Example manifests, values files and SQL
│   └── reference/                        CRD API reference, Helm values, ports and names
├── upstream/
│   ├── starrocks/                        StarRocks docs/en, branch-4.1, unmodified
│   ├── starrocks-kubernetes-operator/    Operator docs, examples, chart values, manifests, unmodified
│   └── data-on-eks/                      AWS Data on EKS StarRocks docs and manifests, unmodified
├── LICENSE                               Apache License 2.0
├── NOTICE                                Attribution for upstream content
└── PROVENANCE.md                         Source repositories, commits, paths, exclusions
```

## Versions covered

| Component | Version at copy time |
|---|---|
| StarRocks documentation | `branch-4.1` |
| StarRocks Kubernetes Operator | chart and operator image `1.11.8` |
| CRD API | `starrocks.com/v1` |
| AWS Data on EKS StarRocks stack | `main` (pins operator `v1.11.3`, StarRocks `3.5-latest`) |

Exact commit hashes are in [PROVENANCE.md](PROVENANCE.md). Defaults change between releases, so check the upstream copy for your version before relying on a default quoted in a guide.

## Using this repository with AI tools

- Point the tool at `guides/` for task questions and at `upstream/` for reference lookups.
- [`guides/17-upstream-doc-map.md`](guides/17-upstream-doc-map.md) maps topics to upstream file paths, which helps a tool find the right page in a tree of about 1,200 Markdown files.
- The operator publishes its API reference as HTML inside a `.md` file. [`guides/reference/crd-api-reference.md`](guides/reference/crd-api-reference.md) is the same content as Markdown tables.
- Upstream StarRocks pages are Docusaurus sources. Some use `.mdx` and import shared snippets from `upstream/starrocks/docs/en/_assets/commonMarkdown/`.

## License

Everything in this repository is licensed under the [Apache License 2.0](LICENSE).

- Content under `upstream/` is copyrighted by its original authors and redistributed here unmodified under the Apache License 2.0. Each upstream directory keeps its own `LICENSE` and, where one exists, `NOTICE` file.
- Content under `guides/` and the root-level files is original to this repository and also under the Apache License 2.0.

See [NOTICE](NOTICE) for attribution.

This repository is not affiliated with or endorsed by StarRocks, CelerData, or Amazon Web Services. StarRocks is a trademark of its owner.
