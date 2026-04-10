#!/usr/bin/env bash
# Package and push the sheep-dog umbrella helm chart to the Nexus OCI helm repo.
#
# Troubleshooting/recovery tool. In the normal release flow the release
# workflow in sheep-dog-ops does this automatically (see #32). Use this when
# the workflow fails partway through and you need to re-publish manually.
#
# Prereqs:
#   - helm installed and on PATH
#   - `helm registry login nexus-docker.sheepdog.io` already run
#     interactively as the current user
#   - hosts file on the runner has `127.0.0.1 nexus-docker.sheepdog.io`
#   - mkcert root CA trusted on this machine (see nexus/import-rootCA.sh)
#   - minikube tunnel running on windows-desktop
#
# Usage:
#   ./release.sh

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chart_dir="${script_dir}/../helm/sheep-dog"
work_dir="${script_dir}/../helm"
registry="oci://nexus-docker.sheepdog.io/helm-hosted"

echo "Packaging chart from ${chart_dir}..."
cd "${work_dir}"
helm package sheep-dog

chart_tgz="$(ls -t sheep-dog-*.tgz 2>/dev/null | head -n 1 || true)"
if [[ -z "${chart_tgz}" ]]; then
    echo "ERROR: no packaged chart found" >&2
    exit 1
fi

echo "Pushing ${chart_tgz} to ${registry}..."
helm push "${chart_tgz}" "${registry}"

echo "Cleaning up ${chart_tgz}..."
rm -f "${chart_tgz}"

echo "Done."
