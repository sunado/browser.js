#!/bin/sh
set -eu

config=/tmp/wisp-config.json

cat >"$config" <<EOF
{
  "allow_private_ips": ${WISP_ALLOW_PRIVATE_IPS:-false},
  "allow_loopback_ips": ${WISP_ALLOW_LOOPBACK_IPS:-false},
  "allow_udp_streams": ${WISP_ALLOW_UDP_STREAMS:-true},
  "allow_tcp_streams": ${WISP_ALLOW_TCP_STREAMS:-true},
  "stream_limit_total": ${WISP_STREAM_LIMIT_TOTAL:--1},
  "stream_limit_per_host": ${WISP_STREAM_LIMIT_PER_HOST:--1}
}
EOF

port="${WISP_INTERNAL_PORT:-5001}"

echo "Starting WISP for ${WISP_DOMAIN:-localhost} on 0.0.0.0:${port}"

exec wisp-js-server \
	-H 0.0.0.0 \
	-P "$port" \
	-L "${WISP_LOG_LEVEL:-INFO}" \
	-C "$config"
