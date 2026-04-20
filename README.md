# Sheep Dog Ops

CI/CD infrastructure for the sheep-dog ecosystem. Provides reusable GitHub Actions workflows that the other repos call for snapshot builds, releases, and deployments. Also includes a custom Maven plugin for managing Xtext project releases where the standard Maven release plugin doesn't work.

## Layout

```
sheep-dog-ops/
├── infra/                         shared infrastructure, one set per ecosystem
│   ├── eks/                       EKS cluster setup/teardown scripts
│   ├── grafana/                   Darmok observability Helm chart (#252, #277)
│   ├── minikube/                  minikube cluster setup/teardown scripts
│   ├── mysql/                     sheep-dog-dev-db image build
│   ├── nexus/                     Nexus Helm values, PV, mkcert CA, post-install config
│   └── ubuntu/                    Ubuntu host provisioning helpers
├── sheep-dog/                     app — the deployable sheep-dog stack (umbrella Helm chart + deploy scripts)
└── sheep-dog-mgmt-maven-plugin/   standalone tool — Xtext release coordination
```

Rules the shape expresses:
- **App folders** at the top level (one per deployable application; `sheep-dog/` today, `tamarian/` to follow).
- **`infra/`** is the single bucket for shared infrastructure, with product-named subfolders. Not split by cicd-vs-ops — Nexus and Grafana each serve both concerns.
- **Standalone tools** stay at the top level.

## Projects

| Project | Description |
|---------|-------------|
| sheep-dog-mgmt-maven-plugin | Management Maven plugin for release coordination |

## Reusable Workflows

The `.github/workflows/` directory contains reusable workflows called by the other repos:

| Workflow | Purpose |
|----------|---------|
| snapshot-maven.yml | Deploy Maven snapshot artifacts to GitHub Packages |
| snapshot-docker.yml | Build and push Docker snapshot images |
| snapshot-gradle.yml | Deploy Gradle snapshot artifacts |
| release-maven.yml | Run Maven release plugin to tag and publish a release |
| release-gradle.yml | Run Gradle release to tag and publish a release |
| merge.yml | Merge automation between branches |
| deploy.yml | Deploy services to Kubernetes |

## Build Command

Run `scripts/install.bat` in the `sheep-dog-mgmt-maven-plugin` directory.
