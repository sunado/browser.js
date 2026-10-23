#!/usr/bin/env bash
# Wrapper around docker-compose that derives all service URLs from a single
# MAIN_DOMAIN in .env.
#
# Usage:
#   ./scripts/compose.sh up -d
#   ./scripts/compose.sh logs -f
#   ./scripts/compose.sh down
#   ./scripts/compose.sh config
#
# With no arguments it runs: up -d --build
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [ -f .env ]; then
	set -a
	# shellcheck disable=SC1091
	. ./.env
	set +a
fi

MAIN_DOMAIN="${MAIN_DOMAIN:-localhost}"
FRONTEND_SUBDOMAIN="${FRONTEND_SUBDOMAIN:-app}"
WISP_SUBDOMAIN="${WISP_SUBDOMAIN:-wisp}"

FRONTEND_DOMAIN="${FRONTEND_DOMAIN:-${FRONTEND_SUBDOMAIN}.${MAIN_DOMAIN}}"
WISP_DOMAIN="${WISP_DOMAIN:-${WISP_SUBDOMAIN}.${MAIN_DOMAIN}}"
WISP_URL="${WISP_URL:-wss://${WISP_DOMAIN}/}"

export MAIN_DOMAIN FRONTEND_SUBDOMAIN WISP_SUBDOMAIN
export FRONTEND_DOMAIN WISP_DOMAIN WISP_URL

if docker compose version >/dev/null 2>&1; then
	compose=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
	compose=(docker-compose)
else
	echo "error: Docker Compose is not installed" >&2
	exit 1
fi

echo "Frontend domain: ${FRONTEND_DOMAIN} (${FRONTEND_BIND:-127.0.0.1}:${FRONTEND_PORT:-8080})"
echo "WISP URL:        ${WISP_URL} (${WISP_BIND:-127.0.0.1}:${WISP_PORT:-8081})"

if [ "$#" -eq 0 ]; then
	set -- up -d --build
fi

exec "${compose[@]}" "$@"
