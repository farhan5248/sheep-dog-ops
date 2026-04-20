#!/bin/bash
# Idempotent MySQL init: run every container start so that pre-existing
# volumes with partial state (e.g. user present but no grants) get corrected.
# All statements use IF NOT EXISTS / idempotent forms so re-runs are harmless.
set -e

echo "Ensuring MBT database, user, and grants exist..."
mysql -u root -proot <<'SQL'
CREATE DATABASE IF NOT EXISTS mbt;
CREATE USER IF NOT EXISTS 'mbt'@'%' IDENTIFIED BY 'mbt';
GRANT ALL PRIVILEGES ON mbt.* TO 'mbt'@'%';
FLUSH PRIVILEGES;
SQL

echo "MBT database init complete."
