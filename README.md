# Sheep Dog Ops

Operations repo with reusable GitHub Actions workflows and release management.

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
