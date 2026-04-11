#!/usr/bin/env bash
# Run the sheep-dog smoke test: asciidoctor-to-uml maven build against the
# deployed ingress, used after setup-namespace to verify the namespace is
# healthy end-to-end.
#
# Usage: smoke-test.sh <host> [features-dir]
#   host         — ingress hostname (e.g. dev.sheepdog.io) or LB DNS
#   features-dir — optional; defaults to the sheep-dog-specs sibling checkout

set -euo pipefail

HOST="${1:-}"
if [[ -z "$HOST" ]]; then
    echo "Usage: smoke-test.sh <host> [features-dir]"
    echo "Example: smoke-test.sh qa.sheepdog.io"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FEATURES_DIR="${2:-$SCRIPT_DIR/../../../sheep-dog-specs/sheep-dog-features}"

if [[ ! -d "$FEATURES_DIR" ]]; then
    echo "sheep-dog-features directory not found: $FEATURES_DIR"
    exit 1
fi

cd "$FEATURES_DIR"
mvn org.farhan:sheep-dog-svc-maven-plugin:asciidoctor-to-uml \
    -Dtags="svc-maven-plugin" \
    -Dhost="$HOST"
