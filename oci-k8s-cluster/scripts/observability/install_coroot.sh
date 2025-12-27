#!/bin/bash
OBS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Define SCRIPT_DIR for common.sh if not set (e.g. running directly)
if [ -z "${SCRIPT_DIR:-}" ]; then
  SCRIPT_DIR="$( cd "$OBS_DIR/../.." && pwd )"
fi
source "$OBS_DIR/../../common.sh"

install_coroot() {
  echo -e "${BLUE}Installing Coroot Observability (Full Stack - Profiling/Traces/Logs) on REMOTE MASTER...${NC}"

  run_remote_stream "$MASTER_NODE" 'bash -s' <<'EOF'
    set -e
    # Colors for remote
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    NC='\033[0m'

    echo -e "${YELLOW}Adding Coroot Helm Repo...${NC}"
    helm repo add coroot https://coroot.github.io/helm-charts
    helm repo update

    # Create namespace
    kubectl create ns coroot --dry-run=client -o yaml | kubectl apply -f -

    echo -e "${YELLOW}Deploying Coroot via Helm (Prometheus for metrics, NO ClickHouse via Helm)...${NC}"
    helm upgrade --install coroot coroot/coroot \
      --namespace coroot \
      --set clickhouse.enabled=false \
      --set prometheus.enabled=true \
      --set prometheus.server.persistentVolume.enabled=true \
      --set prometheus.server.persistentVolume.size=2Gi \
      --set prometheus.server.persistentVolume.storageClass=longhorn-2 \
      --set prometheus.server.resources.requests.memory=256Mi \
      --set prometheus.server.resources.limits.memory=1Gi \
      --set corootCE.image.tag="1.17.6" \
      --set corootCE.persistentVolume.size=1Gi \
      --set corootCE.persistentVolume.storageClassName=longhorn-2 \
      --set corootCE.resources.requests.memory=256Mi \
      --set corootCE.resources.limits.memory=1Gi \
      --set corootCE.ingress.enabled=true \
      --set "corootCE.ingress.hosts[0].host=coroot.dnor.io" \
      --set "corootCE.ingress.hosts[0].paths[0].path=/" \
      --set "corootCE.ingress.hosts[0].paths[0].pathType=Prefix" \
      --set corootCE.ingress.className=nginx \
      --set "corootCE.ingress.tls[0].hosts[0]=coroot.dnor.io" \
      --set "corootCE.ingress.tls[0].secretName=coroot-tls" \
      --set "corootCE.ingress.annotations.cert-manager\.io/cluster-issuer=dnor-ca-issuer"

    echo -e "${BLUE}Deploying standalone ClickHouse with passwordless config...${NC}"
    
    # Create ClickHouse users config (passwordless auth)
    cat <<CLICKHOUSE_CONFIG | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: clickhouse-users-config
  namespace: coroot
data:
  users.xml: |
    <clickhouse>
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

    # Create ClickHouse Service
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

    # Create ClickHouse Deployment (emptyDir to avoid Longhorn issues)
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

    echo -e "${BLUE}Configuring Coroot to use ClickHouse...${NC}"
    # Add ClickHouse env vars to Coroot (NO PASSWORD)
    kubectl set env deployment/coroot -n coroot \
      BOOTSTRAP_CLICKHOUSE_ADDRESS=clickhouse:9000 \
      BOOTSTRAP_CLICKHOUSE_USER=default \
      BOOTSTRAP_CLICKHOUSE_DATABASE=default

    echo -e "${BLUE}Waiting for pods to be ready...${NC}"
    kubectl wait --for=condition=ready pod -l app=clickhouse -n coroot --timeout=180s
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=coroot -n coroot --timeout=180s

    echo -e "${GREEN}Coroot with full ClickHouse stack installed successfully!${NC}"
    echo -e "${GREEN}Features enabled: Profiling, Traces, Logs, Metrics, Service Map${NC}"
EOF

  echo -e "${GREEN}Coroot is Ready!${NC}"
  echo -e "${YELLOW}Access: https://coroot.dnor.io${NC}"
  echo -e "${GREEN}✓ Agent Detection${NC}"
  echo -e "${GREEN}✓ Applications & Service Map${NC}"
  echo -e "${GREEN}✓ Prometheus Metrics${NC}"
  echo -e "${GREEN}✓ ClickHouse Profiling${NC}"
  echo -e "${GREEN}✓ Distributed Tracing${NC}"
  echo -e "${GREEN}✓ Log Aggregation${NC}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_coroot
fi
