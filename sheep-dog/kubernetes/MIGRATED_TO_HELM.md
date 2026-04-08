# Migrated to Helm

The manifests in this directory are **no longer the source of truth**. They have been migrated to a Helm umbrella chart at `../helm/sheep-dog/`.

These kustomize files are kept temporarily as a reference while the new Helm-based flow stabilizes (see #29). They will be deleted in a few weeks.

## What replaced what

| Old kustomize path | New Helm path |
|---|---|
| `shared/base/db-*.yaml`, `amq-*.yaml`, `ingress.yaml` | `../helm/sheep-dog/templates/db-*.yaml`, `amq-*.yaml`, `ingress.yaml` |
| `shared/overlays/dev/ingress-patch.yaml` | `../helm/helm-values/values-dev.yaml` (`ingress.host: dev.sheepdog.io`) |
| `shared/overlays/qa/ingress-patch.yaml` | `../helm/helm-values/values-qa.yaml` (`ingress.host: qa.sheepdog.io`) |
| `shared/overlays/prod/db-pvc-patch.yaml` (`gp2`) | `../helm/helm-values/values-prod.yaml` (`pvcStorageClass: gp2`) |
| `complete/base/...` (whole stack kustomize) | `../helm/sheep-dog/` (whole stack umbrella chart) |
| `complete/overlays/prod/` | `../helm/helm-values/values-prod.yaml` |

## How to deploy now

```bash
cd ..
helm upgrade --install sheep-dog ./helm/sheep-dog -n <namespace> --create-namespace -f ./helm/helm-values/values-<namespace>.yaml
```

See `../helm/README.md` for full usage and `tools.overview.md` for the cross-cutting documentation.
