# syntax=docker/dockerfile:1.7
#
# Reproduces the build job and frontend job from .github/workflows/main.yml.
#
# Usage:
#   WISP_URL=wss://wisp.example.com/ ./scripts/docker-build.sh
#   OUT_DIR=/tmp/out ./scripts/docker-build.sh
#
# For the full runtime stack (frontend + WISP), see docker-compose.yml and
# scripts/compose.sh.
#
# The WISP URL is baked into the frontend at build time. It can also be set
# directly with: --build-arg VITE_WISP_URL=wss://wisp.example.com/
#
# Building directly with Docker (without the helper script) requires the
# local exporter, otherwise the resulting image is an empty scratch image:
#   docker build --target export --output type=local,dest=dist \
#     --build-arg VITE_WISP_URL=wss://wisp.example.com/ .

ARG NODE_VERSION=24

FROM node:${NODE_VERSION}-bookworm AS build

ARG WASM_BINDGEN_VERSION=0.2.105
ARG BINARYEN_VERSION=123
ARG TARGETARCH

ENV CI=true \
	DEBIAN_FRONTEND=noninteractive \
	RUSTUP_HOME=/usr/local/rustup \
	CARGO_HOME=/usr/local/cargo \
	PATH=/usr/local/cargo/bin:$PATH

# Toolchain required by packages/scramjet/.github/actions/setup-rewriter-toolchain
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		build-essential \
		ca-certificates \
		curl \
		git \
		python3 \
		xz-utils \
	&& rm -rf /var/lib/apt/lists/*

# Matches packageManager in package.json
RUN npm install -g pnpm@10.12.1

# The rewriter uses a nightly toolchain with build-std support (rust-src).
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
		| sh -s -- -y --no-modify-path --profile minimal --default-toolchain nightly \
	&& rustup component add rust-src --toolchain nightly \
	&& rustup target add wasm32-unknown-unknown --toolchain nightly

# wasm-opt (binaryen) and wasm-bindgen-cli, equivalent to the
# setup-binaryen and cargo install steps in CI. Prebuilt binaries keep the
# image build reasonably fast.
RUN set -eux; \
	case "${TARGETARCH}" in \
		amd64) BINARYEN_ARCH=x86_64; WBG_ARCH=x86_64 ;; \
		arm64) BINARYEN_ARCH=aarch64; WBG_ARCH=aarch64 ;; \
		*) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
	esac; \
	curl -fsSL "https://github.com/WebAssembly/binaryen/releases/download/version_${BINARYEN_VERSION}/binaryen-version_${BINARYEN_VERSION}-${BINARYEN_ARCH}-linux.tar.gz" \
		| tar -xz -C /opt; \
	ln -s /opt/binaryen-version_${BINARYEN_VERSION}/bin/* /usr/local/bin/; \
	curl -fsSL "https://github.com/wasm-bindgen/wasm-bindgen/releases/download/${WASM_BINDGEN_VERSION}/wasm-bindgen-${WASM_BINDGEN_VERSION}-${WBG_ARCH}-unknown-linux-musl.tar.gz" \
		| tar -xz -C /opt; \
	ln -s "/opt/wasm-bindgen-${WASM_BINDGEN_VERSION}-${WBG_ARCH}-unknown-linux-musl/wasm-bindgen" /usr/local/bin/wasm-bindgen

RUN --mount=type=cache,target=/usr/local/cargo/registry \
	--mount=type=cache,target=/usr/local/cargo/git \
	cargo install --git https://github.com/r58playz/wasm-snip

WORKDIR /app

# Copy only the workspace manifests first so dependency installation stays
# cached when source files change.
COPY pnpm-lock.yaml pnpm-workspace.yaml ./
COPY package.json ./
COPY external/dreamlandjs/package.json external/dreamlandjs/
COPY packages/cdp/package.json packages/cdp/
COPY packages/chrome/package.json packages/chrome/
COPY packages/inject/package.json packages/inject/
COPY packages/scramjet/package.json packages/scramjet/
COPY packages/scramjet/packages/bootstrap/package.json packages/scramjet/packages/bootstrap/
COPY packages/scramjet/packages/controller/package.json packages/scramjet/packages/controller/
COPY packages/scramjet/packages/core/package.json packages/scramjet/packages/core/
COPY packages/scramjet/packages/create-proxy-app/package.json packages/scramjet/packages/create-proxy-app/
COPY packages/scramjet/packages/demo/package.json packages/scramjet/packages/demo/
COPY packages/scramjet/packages/rpc/package.json packages/scramjet/packages/rpc/
COPY packages/scramjet/packages/runway/package.json packages/scramjet/packages/runway/
COPY packages/scramjet/packages/utils/package.json packages/scramjet/packages/utils/
COPY packages/scramjet/patches packages/scramjet/patches
COPY scripts scripts

RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
	pnpm install --frozen-lockfile

COPY . .

# Git submodules are expected to be checked out on the host (the helper script
# validates this before invoking Docker).

WORKDIR /app/packages/scramjet/packages/core
# "Pack Scramjet" - prepack runs the release rewriter build and rspack build.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
	--mount=type=cache,target=/usr/local/cargo/git \
	--mount=type=cache,target=/app/packages/scramjet/packages/core/rewriter/target \
	pnpm pack

WORKDIR /app/packages/scramjet/packages/controller
# "Pack Scramjet Controller"
RUN pnpm pack

# "Build Frontend"
WORKDIR /app
RUN pnpm build:dreamland

RUN SKIP_CORE=1 pnpm build

ARG VITE_WISP_URL
ARG VITE_ISOLATION_ORIGIN="none"

RUN test -n "${VITE_WISP_URL}" || { \
	echo "error: VITE_WISP_URL is required (e.g. --build-arg VITE_WISP_URL=wss://wisp.example.com/)" >&2; \
	exit 1; \
	}

RUN VITE_WISP_URL="${VITE_WISP_URL}" \
	VITE_ISOLATION_ORIGIN="${VITE_ISOLATION_ORIGIN}" \
	pnpm build:chrome

# Runtime image for the static frontend, used by docker-compose.yml.
FROM nginx:alpine AS frontend

ENV FRONTEND_DOMAIN=localhost \
	FRONTEND_INTERNAL_PORT=80

COPY docker/frontend/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/packages/chrome/dist/ /usr/share/nginx/html/

EXPOSE 80

# Collected build outputs. Use `--output type=local` (the helper script does
# this) to export them to the host.
FROM scratch AS export

COPY --from=build /app/packages/scramjet/packages/core/dist/ /scramjet/core/dist/
COPY --from=build /app/packages/scramjet/packages/core/mercuryworkshop-scramjet-*.tgz /scramjet/core/
COPY --from=build /app/packages/scramjet/packages/controller/dist/ /scramjet/controller/dist/
COPY --from=build /app/packages/scramjet/packages/controller/mercuryworkshop-scramjet-controller-*.tgz /scramjet/controller/
COPY --from=build /app/packages/chrome/dist/ /chrome/dist/
