FROM prom/prometheus:latest

# Install envsubst (part of gettext package)
USER root
RUN apk add --no-cache gettext

# Copy config template and entrypoint script
COPY prometheus.yml.template /etc/prometheus/prometheus.yml.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER nobody

ENTRYPOINT ["/entrypoint.sh"]
