#!/bin/sh
set -e

# Substitute environment variables in promtail config
envsubst < /etc/promtail/promtail-config.yaml.template > /etc/promtail/promtail-config.yaml

# Start Promtail with all arguments passed to this script
exec /usr/bin/promtail "$@"
