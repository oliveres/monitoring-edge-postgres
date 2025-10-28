# Edge Monitoring Stack (PostgreSQL)

Monitoring agent for Docker hosts with PostgreSQL/TimescaleDB. Includes all features from edge-basic plus PostgreSQL metrics collection.

## Components

- **Prometheus Agent**: Scrapes metrics and forwards via remote write (0 local retention)
- **Promtail**: Collects container logs and forwards to central Loki
- **cAdvisor**: Collects Docker container metrics
- **Node Exporter**: Collects host system metrics
- **PostgreSQL Exporter**: Collects PostgreSQL/TimescaleDB metrics with custom queries

## Requirements

- Docker 20.10+
- Docker Compose 2.0+
- Access to central monitoring server (VPC or internet)
- PostgreSQL/TimescaleDB database accessible from this host
- External Docker network `dispatch-network` (for PostgreSQL connection)
- Minimal resources: 512MB RAM, 1 vCPU

## Deployment

### Option 1: Portainer GitOps (Recommended)

1. Create this repository on GitHub
2. Ensure `dispatch-network` exists:
   ```bash
   docker network create dispatch-network
   ```
3. In Portainer on edge host, go to **Stacks** → **Add stack**
4. Select **Git Repository**
5. Configure:
   - **Name**: `monitoring-edge`
   - **Repository URL**: `https://github.com/YOUR-USERNAME/monitoring-edge-postgres`
   - **Branch**: `main`
6. Add environment variables (see below)
7. Enable **GitOps** for auto-updates
8. Deploy

### Option 2: Manual Deployment

```bash
git clone https://github.com/YOUR-USERNAME/monitoring-edge-postgres.git
cd monitoring-edge-postgres

# Ensure dispatch-network exists
docker network create dispatch-network

# Create .env file
cp .env.example .env
nano .env

# Deploy
docker-compose up -d

# Check status
docker-compose ps
```

## Environment Variables

### For DigitalOcean VPC Setup (Recommended)

```env
# Unique hostname for this edge host
HOSTNAME=edge-pg-host-1

# Central server VPC private IPs
CENTRAL_PROMETHEUS_URL=http://10.116.0.2:9090/api/v1/write
CENTRAL_LOKI_URL=http://10.116.0.2:3100/loki/api/v1/push

# PostgreSQL connection
POSTGRES_DATA_SOURCE_NAME=postgresql://user:password@postgres-host:5432/dbname?sslmode=disable

# No authentication needed for VPC
```

### For Remote VPS (HTTPS + Basic Auth)

```env
# Unique hostname for this edge host
HOSTNAME=remote-pg-vps-1

# Central server public URLs
CENTRAL_PROMETHEUS_URL=https://monitoring.example.com/prometheus/api/v1/write
CENTRAL_LOKI_URL=https://monitoring.example.com/loki/api/v1/push

# PostgreSQL connection
POSTGRES_DATA_SOURCE_NAME=postgresql://user:password@postgres-host:5432/dbname?sslmode=disable

# Basic authentication credentials
BASIC_AUTH_USER=remote
BASIC_AUTH_PASSWORD=your-password
```

## PostgreSQL Connection String

Format: `postgresql://username:password@hostname:port/database?sslmode=disable`

### Examples:

**Local PostgreSQL:**
```env
POSTGRES_DATA_SOURCE_NAME=postgresql://postgres:password@localhost:5432/mydatabase?sslmode=disable
```

**PostgreSQL in Docker (same Portainer stack):**
```env
POSTGRES_DATA_SOURCE_NAME=postgresql://postgres:password@postgres:5432/mydatabase?sslmode=disable
```

**PostgreSQL on separate host:**
```env
POSTGRES_DATA_SOURCE_NAME=postgresql://monitoring_user:secure_pass@192.168.1.100:5432/production_db?sslmode=disable
```

**With SSL enabled:**
```env
POSTGRES_DATA_SOURCE_NAME=postgresql://user:password@host:5432/db?sslmode=require
```

### Create Monitoring User in PostgreSQL

For security, create a dedicated monitoring user with read-only access:

```sql
-- Connect to PostgreSQL as superuser
CREATE USER monitoring_user WITH PASSWORD 'secure_password';

-- Grant necessary permissions
GRANT CONNECT ON DATABASE your_database TO monitoring_user;
GRANT USAGE ON SCHEMA public TO monitoring_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO monitoring_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO monitoring_user;

-- For TimescaleDB specific views
GRANT SELECT ON ALL TABLES IN SCHEMA timescaledb_information TO monitoring_user;
GRANT SELECT ON ALL TABLES IN SCHEMA meters TO monitoring_user;  -- If using custom schema
```

## Custom TimescaleDB Queries

This exporter includes custom queries for TimescaleDB monitoring in `postgres-exporter/queries.yaml`:

### Monitored Metrics:
- **Chunk metrics**: Age, size, compression status of hypertable chunks
- **Hypertable stats**: Chunk count, compression settings
- **Background jobs**: Compression/retention job status and success rates
- **Custom views**: Application-specific metrics from custom database views

### Customize Queries

Edit `postgres-exporter/queries.yaml` to add your own queries:

```yaml
custom_query_name:
  query: "SELECT metric::text, value::float FROM your_view"
  metrics:
    - metric:
        usage: "LABEL"
        description: "Metric name"
    - value:
        usage: "GAUGE"
        description: "Metric value"
```

After changes, redeploy stack.

## Verification

### Check Container Status

```bash
# All containers should be running
docker ps | grep monitoring

# Expected containers:
# - monitoring-prometheus
# - monitoring-promtail
# - monitoring-cadvisor
# - monitoring-node-exporter
# - monitoring-postgres-exporter ← Additional
```

### Check Logs

```bash
# PostgreSQL Exporter - should connect successfully
docker logs monitoring-postgres-exporter
# Expected: "Listening on :9187" (no connection errors)

# Prometheus - should scrape postgres exporter
docker logs monitoring-prometheus | grep postgres
# Expected: Successful scrapes from postgres-exporter:9187

# Check other components (same as edge-basic)
docker logs monitoring-prometheus | grep "remote write"
docker logs monitoring-promtail | grep "Successfully sent"
```

### Test PostgreSQL Connection

```bash
# Connect to database from container
docker exec monitoring-postgres-exporter \
  psql "$POSTGRES_DATA_SOURCE_NAME" -c "SELECT version();"

# Should show PostgreSQL version
```

### Verify in Grafana

1. Open central Grafana: `https://monitoring.example.com`
2. Go to **Explore** → **Prometheus**
3. Run query:
   ```promql
   pg_up{host="edge-pg-host-1"}
   ```
4. Should return `1` (database is up)

5. Check TimescaleDB metrics:
   ```promql
   pg_chunk_size_bytes{host="edge-pg-host-1"}
   ```
6. Should see chunk sizes

## Metrics Collected

### From PostgreSQL Exporter

Standard PostgreSQL metrics:
- Database size, connections, transactions
- Table statistics (sequential/index scans, inserts, updates, deletes)
- Lock statistics
- Replication lag (if applicable)

Custom TimescaleDB metrics:
- Hypertable chunk count and sizes
- Compression ratios
- Background job status
- Custom application metrics

Collection frequency: Every 10 seconds

### From Other Exporters

Same as edge-basic stack:
- cAdvisor: Container metrics (10s interval)
- Node Exporter: Host metrics (15s interval)

## Troubleshooting

### PostgreSQL Exporter Connection Failed

```bash
# Check logs
docker logs monitoring-postgres-exporter

# Common errors:
# 1. "connection refused" - Wrong host/port
# 2. "authentication failed" - Wrong username/password
# 3. "database does not exist" - Wrong database name
# 4. "no route to host" - Network configuration issue

# Test connection manually
docker exec monitoring-postgres-exporter \
  psql "$POSTGRES_DATA_SOURCE_NAME" -c "SELECT 1;"
```

### Network Issues

```bash
# Verify dispatch-network exists
docker network ls | grep dispatch

# If missing, create it
docker network create dispatch-network

# Check postgres-exporter is on both networks
docker inspect monitoring-postgres-exporter | grep -A 10 Networks
# Should show: monitoring AND dispatch-network
```

### PostgreSQL Permissions

```sql
-- Check user permissions in PostgreSQL
\du monitoring_user

-- Grant missing permissions
GRANT SELECT ON ALL TABLES IN SCHEMA timescaledb_information TO monitoring_user;
```

### Custom Queries Failing

```bash
# Check exporter logs for query errors
docker logs monitoring-postgres-exporter | grep -i error

# Common issues:
# 1. View doesn't exist - Create missing views
# 2. Permission denied - Grant SELECT permissions
# 3. Syntax error - Fix query in queries.yaml

# Test query manually in PostgreSQL
psql "$POSTGRES_DATA_SOURCE_NAME" -c "SELECT * FROM meters.grafana_system_status;"
```

### High Memory Usage

If PostgreSQL exporter uses excessive memory:

```yaml
# In docker-compose.yml, add resource limits:
postgres-exporter:
  deploy:
    resources:
      limits:
        memory: 256M
        cpus: '0.5'
```

## Grafana Dashboards

Import these dashboards for PostgreSQL monitoring:

- **Dashboard ID 9628**: PostgreSQL Database Dashboard
- Includes: connections, transactions, cache hit rate, locks, replication

For TimescaleDB-specific metrics, create custom dashboard with queries like:

```promql
# Number of chunks
pg_num_chunks{host="$host"}

# Compression ratio
pg_compressed_chunks{host="$host"} / pg_num_chunks{host="$host"}

# Job failures
rate(pg_total_failures{host="$host"}[5m])
```

## Security

1. **Use dedicated monitoring user**: Don't use superuser or application user
2. **Read-only permissions**: Monitoring user should only have SELECT
3. **Secure password**: Use strong password in connection string
4. **SSL recommended**: Use `sslmode=require` for production
5. **Network isolation**: Use private network (VPC or dispatch-network)

## Advanced Configuration

### Monitor Multiple Databases

Edit `docker-compose.yml` environment:

```yaml
PG_EXPORTER_AUTO_DISCOVER_DATABASES: "true"
PG_EXPORTER_INCLUDE_DATABASES: "db1,db2,db3"
```

Or use separate exporter instance per database.

### Exclude Noisy Tables

In `queries.yaml`, add WHERE clauses:

```yaml
query: |
  SELECT ... FROM pg_stat_user_tables
  WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
```

### Add Custom Application Metrics

Create materialized view in PostgreSQL:

```sql
CREATE MATERIALIZED VIEW meters.prometheus_app_metrics AS
SELECT
  'active_users'::text as metric_name,
  COUNT(*)::float as value
FROM users WHERE last_seen > now() - interval '5 minutes';

-- Refresh periodically (e.g., via cron or TimescaleDB continuous aggregate)
```

Add to `queries.yaml`:

```yaml
app_metrics:
  query: "SELECT metric_name::text, value::float FROM meters.prometheus_app_metrics"
  metrics:
    - metric_name:
        usage: "LABEL"
    - value:
        usage: "GAUGE"
```

## Resource Optimization

For large databases:

1. **Increase scrape interval**:
   ```yaml
   # In prometheus/prometheus.yml
   - job_name: 'postgres'
     scrape_interval: 30s  # From 10s
   ```

2. **Disable unnecessary metrics**:
   ```yaml
   # In docker-compose.yml
   PG_EXPORTER_DISABLE_SETTINGS_METRICS: "true"
   ```

3. **Limit auto-discovery**:
   ```yaml
   PG_EXPORTER_INCLUDE_DATABASES: "main_db"  # Only specific databases
   ```

## Getting Help

- Check [../docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md)
- Review logs: `docker-compose logs`
- PostgreSQL Exporter docs: https://github.com/prometheus-community/postgres_exporter
- TimescaleDB docs: https://docs.timescale.com/

## License

MIT License
