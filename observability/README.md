# observability

Helm chart for the Darmok observability stack. Tracks sheep-dog-main#252 (SPC dashboard) and #277 (centralised logging).

## Contents

Today (step 3a of #252):
- Grafana 12.3.1 via upstream chart `grafana/grafana:10.5.15` — default config, no plugins or provisioning yet.

Coming in later steps of #252:
- 3b — Datasource + dashboard provisioning as code (ConfigMap + sidecar).
- 3c — Transport that exposes Darmok's `target/darmok/metrics.csv` to Grafana.
- 3d — Infinity datasource plugin pointing at 3c's transport.
- 3e — KensoBI SPC panel plugin + XmR dashboard over cycle-time metrics.

Coming in #277 (next milestone):
- Loki + Promtail/Alloy for centralised logs.
- Prometheus + Pushgateway for metrics push from Darmok batch runs.

## Install

```bash
cd sheep-dog-ops/observability
helm dependency update helm/observability
helm install observability helm/observability \
  --namespace observability --create-namespace
```

## Verify (step 3a smoke test)

```bash
kubectl -n observability get pods
# NAME                                    READY  STATUS  RESTARTS
# observability-grafana-xxxxxxxxxx-xxxxx  1/1    Running 0

kubectl -n observability port-forward svc/observability-grafana 3000:80
# then open http://localhost:3000
```

Username `admin`. Fetch the generated password:

```bash
kubectl -n observability get secret observability-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

Login should land on the empty Grafana home page.

## Uninstall

```bash
helm -n observability uninstall observability
kubectl delete namespace observability
```
