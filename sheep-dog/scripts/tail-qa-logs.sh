#!/bin/bash
# Tail QA-namespace service logs from the host without remembering minikube paths.
#
# Usage:
#   ./tail-qa-logs.sh <service> [tail-args...]
#
# Service is one of: asciidoc, cucumber-gen, mcp
# Extra args are passed through to tail (default: -f -n 100).
#
# Examples:
#   ./tail-qa-logs.sh asciidoc
#   ./tail-qa-logs.sh cucumber-gen -n 500
#   ./tail-qa-logs.sh mcp -f -n 50

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <asciidoc|cucumber-gen|mcp> [tail-args...]" >&2
    exit 1
fi

svc="$1"; shift

case "$svc" in
    asciidoc)     pvc="sheep-dog-asciidoc-api-svc-pvc";  log="sheep-dog-asciidoc-api-svc.log" ;;
    cucumber-gen) pvc="sheep-dog-cucumber-gen-svc-pvc";  log="sheep-dog-cucumber-gen-svc.log" ;;
    mcp)          pvc="sheep-dog-mcp-svc-pvc";           log="sheep-dog-mcp-svc.log" ;;
    *)
        echo "Unknown service: $svc (expected asciidoc, cucumber-gen, or mcp)" >&2
        exit 1
        ;;
esac

path="/tmp/hostpath-provisioner/qa/${pvc}/${log}"
args=("$@")
if [[ ${#args[@]} -eq 0 ]]; then
    args=(-f -n 100)
fi

exec minikube ssh "tail ${args[*]} '${path}'"
