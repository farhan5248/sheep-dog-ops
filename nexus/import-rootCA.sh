#!/usr/bin/env bash
# Imports the mkcert root CA (mkcert-rootCA.pem in this folder) into:
#   1. The system trust store (/usr/local/share/ca-certificates)
#   2. NSS databases for browsers (if libnss3-tools's certutil is present)
#   3. Java cacerts (if JAVA_HOME is set)
# Needed on every client machine that will talk HTTPS to
# nexus.sheepdog.io / nexus-docker.sheepdog.io.
#
# Usage:
#   sudo JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64 ./import-rootCA.sh

set -euo pipefail

CA_FILE="$(cd "$(dirname "$0")" && pwd)/mkcert-rootCA.pem"

if [[ ! -f "$CA_FILE" ]]; then
    echo "ERROR: $CA_FILE not found"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root (use sudo)"
    exit 1
fi

echo "=== 1. Import into system trust store ==="
install -m 644 "$CA_FILE" /usr/local/share/ca-certificates/mkcert-sheepdog.crt
update-ca-certificates

# NSS (Firefox, Chrome profile trust) -- only if certutil from libnss3-tools
# is installed. Walks the invoking user's ~/.pki/nssdb if it exists.
if command -v certutil >/dev/null 2>&1; then
    if [[ -n "${SUDO_USER:-}" ]]; then
        USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        NSS_DB="$USER_HOME/.pki/nssdb"
        if [[ -d "$NSS_DB" ]]; then
            echo "=== 2. Import into NSS at $NSS_DB ==="
            certutil -A -d "sql:$NSS_DB" -t "C,," -n "mkcert-sheepdog" -i "$CA_FILE" || true
        fi
    fi
else
    echo "NOTE: certutil not found (apt install libnss3-tools) -- skipping NSS import"
fi

if [[ -n "${JAVA_HOME:-}" && -f "$JAVA_HOME/lib/security/cacerts" ]]; then
    echo "=== 3. Import into Java cacerts at $JAVA_HOME/lib/security/cacerts ==="
    # Default cacerts password is "changeit". Tolerate "already exists".
    "$JAVA_HOME/bin/keytool" -importcert -noprompt -trustcacerts \
        -alias mkcert-sheepdog \
        -file "$CA_FILE" \
        -keystore "$JAVA_HOME/lib/security/cacerts" \
        -storepass changeit || true
else
    echo "WARNING: JAVA_HOME not set or cacerts missing -- skipping Java import."
    echo "         Set JAVA_HOME and re-run before Maven deploys to nexus over HTTPS."
fi

echo
echo "Done."
