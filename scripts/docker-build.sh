#!/usr/bin/env bash
# Build the project in Docker and export the artifacts produced by CI.
#
# Usage:
#   WISP_URL=wss://wisp.example.com/ ./scripts/docker-build.sh
#   ./scripts/docker-build.sh --build-arg VITE_WISP_URL=wss://wisp.example.com/
#
# Environment:
#   WISP_URL          WISP websocket URL baked into the frontend (required)
#   ISOLATION_ORIGIN  Origin hosting controller.html, or "none" (default: none)
#   OUT_DIR           Directory to write artifacts to (default: ./dist)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

OUT_DIR="${OUT_DIR:-dist}"
WISP_URL="${WISP_URL:-}"
ISOLATION_ORIGIN="${ISOLATION_ORIGIN:-}"

if ! command -v docker >/dev/null 2>&1; then
	echo "error: docker is not installed or not on PATH" >&2
	exit 1
fi

if ! docker buildx version >/dev/null 2>&1; then
	echo "error: docker buildx is required (needed for --output type=local)" >&2
	exit 1
fi

# The CI checkout uses submodules; Docker cannot fetch them from a local
# context, so verify they are initialized before building.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	missing="$(git submodule status | awk '$1 ~ /^-/ { print $2 }')"
	if [ -n "$missing" ]; then
		echo "error: git submodules are not initialized:" >&2
		echo "$missing" >&2
		echo "run: git submodule update --init --recursive" >&2
		exit 1
	fi
fi

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

if [ -z "$WISP_URL" ] && [[ " $* " != *"VITE_WISP_URL="* ]]; then
	echo "error: a WISP URL is required" >&2
	echo "  WISP_URL=wss://wisp.example.com/ $0" >&2
	echo "  or pass: --build-arg VITE_WISP_URL=wss://wisp.example.com/" >&2
	exit 1
fi

build_args=()
if [ -n "$WISP_URL" ]; then
	build_args+=("--build-arg" "VITE_WISP_URL=${WISP_URL}")
fi
if [ -n "$ISOLATION_ORIGIN" ]; then
	build_args+=("--build-arg" "VITE_ISOLATION_ORIGIN=${ISOLATION_ORIGIN}")
fi

echo "Building Docker image and exporting artifacts to $OUT_DIR"
docker build \
	--target export \
	--output "type=local,dest=${OUT_DIR}" \
	"${build_args[@]}" \
	"$@" \
	.

echo
echo "Artifacts:"
find "$OUT_DIR" -type f -printf '  %P\n' | sort
