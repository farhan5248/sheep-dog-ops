# sheep-dog Helm chart

Umbrella Helm chart for the entire `sheep-dog` stack: shared infra (db, amq, ingress) plus all microservices (asciidoc-api, cucumber-gen, mcp).

Replaces the kustomize layout at `sheep-dog-ops/sheep-dog/kubernetes/` and the per-service `sheep-dog-svc/*/kubernetes/` directories. Those are kept as a reference for a few weeks and will be deleted later.

## Layout

```
helm/
  sheep-dog/            # the chart
    Chart.yaml
    values.yaml         # defaults
    templates/
      db-*.yaml         # MySQL (deployment, pvc, service)
      amq-*.yaml        # ActiveMQ Artemis (deployment, service)
      ingress.yaml      # single ingress routing all service paths
      asciidoc-api-*.yaml
      cucumber-gen-*.yaml
      mcp-*.yaml
  helm-values/          # per-environment overrides (mimics old kustomize overlays/)
    values-dev.yaml
    values-qa.yaml
    values-prod.yaml
```

## Deploy

From `sheep-dog-ops/sheep-dog/helm/`:

```bash
# dev
helm upgrade --install sheep-dog ./sheep-dog -n dev --create-namespace -f helm-values/values-dev.yaml

# qa
helm upgrade --install sheep-dog ./sheep-dog -n qa --create-namespace -f helm-values/values-qa.yaml

# prod (AWS EKS)
helm upgrade --install sheep-dog ./sheep-dog -n prod --create-namespace -f helm-values/values-prod.yaml
```

## Overriding a single service's image tag

Each microservice's `mvn install` builds its own image and needs to roll out only that service. Use `--set` to override just that service's tag:

```bash
helm upgrade --install sheep-dog ./sheep-dog -n dev \
  -f helm-values/values-dev.yaml \
  --set images.mcp.tag=1.2.3
```

The available override keys are:
- `images.db.tag`
- `images.amq.tag`
- `images.asciidocApi.tag`
- `images.cucumberGen.tag`
- `images.mcp.tag`

Helm diffs the full rendered chart against the cluster state and only applies changed resources, so re-running `helm upgrade --install` is safe and cheap.

## Uninstall

```bash
helm uninstall sheep-dog -n <namespace>
```

PVCs are not deleted by `helm uninstall` — remove them explicitly if you want a full clean slate.
