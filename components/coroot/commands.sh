#!/usr/bin/env bash
set -e

# commands.sh for Coroot Component
# Executed by deploy_components.sh

echo "🔭 Setting up Coroot Observability..."

# 1. UPSERT LOGIC: Check if already installed
if kubectl get ns coroot &>/dev/null; then
  echo "    ℹ️  Coroot namespace exists. Running in UPSERT/UPDATE mode..."
else
  echo "    🆕 Fresh installation detected. Creating namespace..."
  kubectl create ns coroot --dry-run=client -o yaml | kubectl apply -f -
fi

echo "    ➕ Adding/Updating Coroot Helm Repo..."
helm repo add coroot https://coroot.github.io/helm-charts
helm repo update

echo "    🚀 Deploying Coroot via Helm..."
# Use 'upgrade --install' for idempotency, referencing local values.yaml
helm upgrade --install coroot coroot/coroot \
  --namespace coroot \
  -f values.yaml

echo "    💾 Deploying/Updating standalone ClickHouse..."

# ClickHouse Users Config (Upsert)
cat <<CLICKHOUSE_CONFIG | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: clickhouse-users-config
  namespace: coroot
data:
  users.xml: |
    <clickhouse>
      <profiles>
        <default>
          <max_threads>2</max_threads>
          <max_distributed_connections>2</max_distributed_connections>
          <background_pool_size>2</background_pool_size>
          <max_memory_usage>1610612736</max_memory_usage> <!-- 1.5GB Soft Limit -->
        </default>
      </profiles>
      <users>
        <default>
          <password></password>
          <networks>
            <ip>::/0</ip>
          </networks>
          <profile>default</profile>
          <quota>default</quota>
        </default>
      </users>
    </clickhouse>
CLICKHOUSE_CONFIG

# ClickHouse Service (Upsert)
cat <<CLICKHOUSE_SVC | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: clickhouse
  namespace: coroot
spec:
  ports:
  - port: 8123
    name: http
  - port: 9000
    name: native
  selector:
    app: clickhouse
CLICKHOUSE_SVC

# ClickHouse Deployment (Upsert)
cat <<CLICKHOUSE_DEPLOY | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: clickhouse
  namespace: coroot
spec:
  replicas: 1
  selector:
    matchLabels:
      app: clickhouse
  template:
    metadata:
      labels:
        app: clickhouse
    spec:
      containers:
      - name: clickhouse
        image: clickhouse/clickhouse-server:24.3
        ports:
        - containerPort: 8123
          name: http
        - containerPort: 9000
          name: native
        volumeMounts:
        - name: data
          mountPath: /var/lib/clickhouse
        - name: users-config
          mountPath: /etc/clickhouse-server/users.d
        resources:
          requests:
            memory: 512Mi
            cpu: 250m
          limits:
            memory: 2Gi
            cpu: 1000m
      volumes:
      - name: data
        emptyDir: {}
      - name: users-config
        configMap:
          name: clickhouse-users-config
CLICKHOUSE_DEPLOY

echo "    🔗 Configuring Coroot Connection..."

# Ensure password env var is REMOVED (fix for upsert/clean state)
kubectl set env deployment/coroot -n coroot BOOTSTRAP_CLICKHOUSE_PASSWORD- 2>/dev/null || true

# Set the correct connection details
kubectl set env deployment/coroot -n coroot \
  BOOTSTRAP_CLICKHOUSE_ADDRESS=clickhouse:9000 \
  BOOTSTRAP_CLICKHOUSE_USER=default \
  BOOTSTRAP_CLICKHOUSE_DATABASE=default

echo "    ⏳ Waiting for pods to be ready..."
# Use wait with a slight delay to allow pod creation
sleep 5
kubectl wait --for=condition=ready pod -l app=clickhouse -n coroot --timeout=300s || echo "⚠️ ClickHouse wait timed out, proceeding..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=coroot -n coroot --timeout=300s || echo "⚠️ Coroot wait timed out, proceeding..."

# AUTOMATIC POSTGRES INTEGRATION
echo "    🐘 Scanning for Postgres deployments to enable Coroot Integration..."
PG_DEPLOYS=$(kubectl get deployments -A -o jsonpath='{range .items[?(@.metadata.name=="postgres-deployment")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}')

if [ ! -z "$PG_DEPLOYS" ]; then
  while read -r NS NAME; do
    echo "       Found Postgres: $NAME in namespace $NS"
    SECRET_NAME=$(kubectl get deployment -n "$NS" "$NAME" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="POSTGRES_USER")].valueFrom.secretKeyRef.name}')
    if [ ! -z "$SECRET_NAME" ]; then
       echo "       ✅ Found credentials secret: $SECRET_NAME. Patching..."
       kubectl patch deployment -n "$NS" "$NAME" --type='merge' -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"coroot.com/postgres-scrape\":\"true\",\"coroot.com/postgres-scrape-credentials-secret-name\":\"$SECRET_NAME\",\"coroot.com/postgres-scrape-credentials-secret-username-key\":\"POSTGRES_USER\",\"coroot.com/postgres-scrape-credentials-secret-password-key\":\"POSTGRES_PASSWORD\"}}}}}"
    else
       echo "       ❌ Could not auto-detect secret for $NAME."
    fi
  done <<< "$PG_DEPLOYS"
else
  echo "       No specific 'postgres-deployment' found."
fi

echo "✅ Coroot setup complete."
