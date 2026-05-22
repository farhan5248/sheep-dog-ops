#!/usr/bin/env bash
# Configure Nexus for hosting helm charts, Maven artifacts, and Docker images.
# Idempotent-ish — Nexus REST returns 4xx on already-exists, which we tolerate.
#
# Prereqs:
#   - Nexus reachable at https://nexus.sheepdog.io (hosts file + minikube
#     tunnel + mkcert root CA trusted in the system store —
#     see sheep-dog-ops/infra/nexus/import-rootCA.sh)
#   - $NEXUS_ADMIN_PW set (Nexus admin password)
#   - $NEXUS_DEPLOY_PW set (password for the helm-deployer user we create)
#
# What this does (Nexus returns 4xx on already-exists, which we tolerate):
#   1. Enable the Docker Bearer Token realm (required for `helm registry login`)
#   2. Create a `helm-hosted` docker-format hosted repo on port 8082
#      (serves both OCI helm charts and Docker container images)
#   3. Create a `nx-helm-deployer` role with permissions on helm-hosted +
#      Maven repos (maven-releases, maven-snapshots, maven-public)
#   4. Create a `helm-deployer` user with that role
#   5. Enable anonymous read access (required for maven-public proxy reads
#      from unauthenticated builds; ships disabled in Nexus 3.71+ CE)
#
# Maven repos (maven-releases, maven-snapshots, maven-central, maven-public)
# ship as Nexus defaults and don't need creation here.
#
# Usage:
#   export NEXUS_ADMIN_PW=...
#   export NEXUS_DEPLOY_PW=...
#   ./configure.sh

set -euo pipefail

NEXUS_URL="https://nexus.sheepdog.io"
ADMIN="admin"

if [[ -z "${NEXUS_ADMIN_PW:-}" ]]; then
    echo "ERROR: NEXUS_ADMIN_PW is not set" >&2
    exit 1
fi
if [[ -z "${NEXUS_DEPLOY_PW:-}" ]]; then
    echo "ERROR: NEXUS_DEPLOY_PW is not set" >&2
    exit 1
fi

# -w prints HTTP status on its own line so failures are easy to eyeball.
CURL_FMT='\n--- HTTP %{http_code} ---\n'

# On Linux, curl uses OpenSSL (not schannel), so --ssl-no-revoke isn't needed.
# mkcert root CA is trusted via /usr/local/share/ca-certificates after
# import-rootCA.sh + update-ca-certificates.

echo "=== 0. Accept Nexus CE EULA ==="
# Nexus 3.71+ ships in CE mode and requires the EULA to be accepted via REST
# before non-trivial operations (anonymous reads work; docker login etc.
# return 403 with "You must accept the EULA..."). The POST must echo back the
# exact disclaimer text from the GET, so we read it and pipe it through.
EULA_PAYLOAD=$(curl -fsS -u "$ADMIN:$NEXUS_ADMIN_PW" "$NEXUS_URL/service/rest/v1/system/eula" |
    python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps({"accepted":True,"disclaimer":d["disclaimer"]}))')
curl -u "$ADMIN:$NEXUS_ADMIN_PW" -X POST \
    "$NEXUS_URL/service/rest/v1/system/eula" \
    -H "Content-Type: application/json" \
    -w "$CURL_FMT" \
    -d "$EULA_PAYLOAD"
echo

echo "=== 1. Enable Docker Bearer Token realm ==="
curl -u "$ADMIN:$NEXUS_ADMIN_PW" -X PUT \
    "$NEXUS_URL/service/rest/v1/security/realms/active" \
    -H "Content-Type: application/json" \
    -w "$CURL_FMT" \
    -d '["NexusAuthenticatingRealm","DockerToken"]'
echo

echo "=== 2. Create helm-hosted docker repo ==="
curl -u "$ADMIN:$NEXUS_ADMIN_PW" -X POST \
    "$NEXUS_URL/service/rest/v1/repositories/docker/hosted" \
    -H "Content-Type: application/json" \
    -w "$CURL_FMT" \
    -d '{"name":"helm-hosted","online":true,"storage":{"blobStoreName":"default","strictContentTypeValidation":true,"writePolicy":"allow"},"docker":{"v1Enabled":false,"forceBasicAuth":false,"httpPort":8082}}'
echo

echo "=== 3. Create nx-helm-deployer role (helm-hosted + Maven repos) ==="
curl -u "$ADMIN:$NEXUS_ADMIN_PW" -X POST \
    "$NEXUS_URL/service/rest/v1/security/roles" \
    -H "Content-Type: application/json" \
    -w "$CURL_FMT" \
    -d '{"id":"nx-helm-deployer","name":"nx-helm-deployer","description":"Deploy to Maven repos and Docker/OCI registry (helm-hosted)","privileges":["nx-repository-view-docker-helm-hosted-*","nx-repository-view-maven2-*-*"],"roles":[]}'
echo

echo "=== 4. Create helm-deployer user ==="
curl -u "$ADMIN:$NEXUS_ADMIN_PW" -X POST \
    "$NEXUS_URL/service/rest/v1/security/users" \
    -H "Content-Type: application/json" \
    -w "$CURL_FMT" \
    -d "{\"userId\":\"helm-deployer\",\"firstName\":\"Helm\",\"lastName\":\"Deployer\",\"emailAddress\":\"helm-deployer@sheepdog.local\",\"password\":\"$NEXUS_DEPLOY_PW\",\"status\":\"active\",\"roles\":[\"nx-helm-deployer\"]}"
echo

echo "=== 5. Enable anonymous read access ==="
# PUT is idempotent — safe to re-run against a Nexus that already has
# anonymous enabled. Required for unauthenticated maven-public proxy reads
# (e.g. publish-eclipse.sh, per-repo snapshot workflows). Surfaced on #393.
curl -u "$ADMIN:$NEXUS_ADMIN_PW" -X PUT \
    "$NEXUS_URL/service/rest/v1/security/anonymous" \
    -H "Content-Type: application/json" \
    -w "$CURL_FMT" \
    -d '{"enabled":true,"userId":"anonymous","realmName":"NexusAuthorizingRealm"}'
echo

echo "Done."
