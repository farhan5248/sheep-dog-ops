#!/usr/bin/env bash
# Build and push the sheep-dog-dev-db image to the Nexus Docker registry.
#
# The umbrella helm chart (sheep-dog-ops/sheep-dog/helm/sheep-dog) pulls
# this image via images.db.repository / images.db.tag in values.yaml.
#
# Prereqs:
#   - Docker running
#   - `docker login nexus-docker.sheepdog.io` already run
#   - hosts file has nexus-docker.sheepdog.io
#   - mkcert root CA trusted on this machine
#
# Usage:
#   ./build.sh [tag]
#
# Default tag is `latest`. Pass a specific version (e.g. `./build.sh 1.0.0`)
# to produce a pinned image, then also push it as `latest`.

set -euo pipefail

IMAGE="nexus-docker.sheepdog.io/sheep-dog-dev-db"
TAG="${1:-latest}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building $IMAGE:$TAG from $SCRIPT_DIR..."
docker image build -f mysql.dockerfile -t "$IMAGE:$TAG" .

echo "Pushing $IMAGE:$TAG..."
docker image push "$IMAGE:$TAG"

if [[ "$TAG" != "latest" ]]; then
    echo "Also tagging as latest and pushing..."
    docker image tag "$IMAGE:$TAG" "$IMAGE:latest"
    docker image push "$IMAGE:latest"
fi

echo "Done."
