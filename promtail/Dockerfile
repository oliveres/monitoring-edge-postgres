FROM grafana/promtail:latest

# Install envsubst (part of gettext package)
USER root
RUN apk add --no-cache gettext

# Copy config template and entrypoint script
COPY promtail-config.yaml.template /etc/promtail/promtail-config.yaml.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER promtail

ENTRYPOINT ["/entrypoint.sh"]
