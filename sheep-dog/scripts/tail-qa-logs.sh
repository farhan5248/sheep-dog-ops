#!/bin/bash
# Tail a sheep-dog service's logs from a client machine without remembering
# minikube paths or pod names.
#
# Targets the cluster by kubectl context, the same way deploy-to-minikube.sh
# does, so this works from ubuntu-client over the registered remote contexts:
#   qa  -> minikube-team     (ubuntu-team)
#   int -> minikube-team     (ubuntu-team — CI/CD integration testing, #455)
#   dev -> minikube-sandbox  (ubuntu-sandbox)
#   *   -> minikube          (local fallback)
#
# Services log to files on a PVC (LOG_PATH=/logs), not stdout, so `kubectl
# logs` returns nothing — we exec into the pod and tail the log file at /logs.
#
# Usage:
#   ./tail-qa-logs.sh <service> [env] [tail-args...]
#
# Service is one of: asciidoc, cucumber-gen, mcp
# env defaults to qa. Extra args are passed through to tail (default: -f -n 100).
#
# Examples:
#   ./tail-qa-logs.sh asciidoc                 # qa, follow last 100
#   ./tail-qa-logs.sh cucumber-gen qa -n 500
#   ./tail-qa-logs.sh mcp dev -f -n 50

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <asciidoc|cucumber-gen|mcp> [env] [tail-args...]" >&2
    exit 1
fi

svc="$1"; shift

# Optional env arg (only consumed if it's a known environment); otherwise qa.
ENV_NAME="qa"
if [[ $# -ge 1 ]]; then
    case "$1" in
        qa|int|dev|*minikube*) ENV_NAME="$1"; shift ;;
    esac
fi

case "$ENV_NAME" in
    qa)  CONTEXT="minikube-team" ;;
    int) CONTEXT="minikube-team" ;;
    dev) CONTEXT="minikube-sandbox" ;;
    *)   CONTEXT="minikube" ;;
esac

case "$svc" in
    asciidoc)     deployment="sheep-dog-asciidoc-api-svc";  log="sheep-dog-asciidoc-api-svc.log" ;;
    cucumber-gen) deployment="sheep-dog-cucumber-gen-svc";  log="sheep-dog-cucumber-gen-svc.log" ;;
    mcp)          deployment="sheep-dog-mcp-svc";           log="sheep-dog-mcp-svc.log" ;;
    *)
        echo "Unknown service: $svc (expected asciidoc, cucumber-gen, or mcp)" >&2
        exit 1
        ;;
esac

args=("$@")
if [[ ${#args[@]} -eq 0 ]]; then
    args=(-f -n 100)
fi

# Resolve the running pod for this deployment in the env namespace.
pod=$(kubectl --context "$CONTEXT" -n "$ENV_NAME" get pods \
    -o jsonpath="{.items[?(@.metadata.labels.app=='sheep-dog')].metadata.name}" 2>/dev/null \
    | tr ' ' '\n' | grep "^${deployment}-" | head -1)

if [[ -z "$pod" ]]; then
    echo "No running pod found for $deployment in context $CONTEXT, namespace $ENV_NAME." >&2
    exit 1
fi

exec kubectl --context "$CONTEXT" -n "$ENV_NAME" exec "$pod" -- tail "${args[@]}" "/logs/${log}"
