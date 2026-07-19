#!/usr/bin/env bash
set -euo pipefail
kind delete cluster --name node-api-demo 2>/dev/null || true
docker rm -f node-api-git-server >/dev/null 2>&1 || true
echo "Local demo torn down."
