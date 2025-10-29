#!/bin/sh
set -e

# Substitute environment variables in prometheus config
envsubst < /etc/prometheus/prometheus.yml.template > /etc/prometheus/prometheus.yml

# Start Prometheus with all arguments passed to this script
exec /bin/prometheus "$@"
