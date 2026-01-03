#!/bin/bash

# Source common variables/functions if they exist
# Assuming running from repo root or scripts dir
OBS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT_DIR="$OBS_DIR"
source "$OBS_DIR/../../common.sh"

install_coroot() {
  echo -e "${BLUE}Installing/Updating Coroot Observability (Full Stack) on REMOTE MASTER...${NC}"

  run_remote_stream "$MASTER_NODE" 'bash -s' <<'EOF'
    set -e
    # Colors for remote
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    RED='\033[0;31m'
    NC='\033[0m'

    # 1. UPSERT LOGIC: Check if already installed
    if kubectl get ns coroot &>/dev/null; then
      echo -e "${YELLOW}Coroot namespace exists. Running in UPSERT/UPDATE mode...${NC}"
      echo -e "${YELLOW}Existing data (ClickHouse/Prometheus) will be PRESERVED.${NC}"
    else
      echo -e "${BLUE}Fresh installation detected. Creating namespace...${NC}"
      kubectl create ns coroot --dry-run=client -o yaml | kubectl apply -f -
    fi

    echo -e "${YELLOW}Adding/Updating Coroot Helm Repo...${NC}"
    helm repo add coroot https://coroot.github.io/helm-charts
    helm repo update

    echo -e "${YELLOW}Deploying Coroot via Helm (Prometheus for metrics, NO ClickHouse via Helm)...${NC}"
    # Use 'upgrade --install' for idempotency
    helm upgrade --install coroot coroot/coroot \
      --namespace coroot \
      --set clickhouse.enabled=false \
      --set prometheus.enabled=true \
      --set prometheus.server.persistentVolume.enabled=true \
      --set prometheus.server.persistentVolume.size=4Gi \
      --set prometheus.server.persistentVolume.storageClass=longhorn-2 \
      --set prometheus.server.global.scrape_interval=30s \
      --set prometheus.server.resources.requests.memory=128Mi \
      --set prometheus.server.resources.limits.memory=1Gi \
      --set corootClusterAgent.resources.requests.memory=256Mi \
      --set corootClusterAgent.resources.limits.memory=1Gi \
      --set corootCE.image.tag="1.17.6" \
      --set corootCE.persistentVolume.size=1Gi \
      --set corootCE.persistentVolume.storageClassName=longhorn-2 \
      --set corootCE.resources.requests.memory=128Mi \
      --set corootCE.resources.limits.memory=1Gi \
      --set corootCE.ingress.enabled=true \
      --set "corootCE.ingress.hosts[0].host=coroot.dnor.io" \
      --set "corootCE.ingress.hosts[0].paths[0].path=/" \
      --set "corootCE.ingress.hosts[0].paths[0].pathType=Prefix" \
      --set corootCE.ingress.className=nginx \
      --set "corootCE.ingress.tls[0].hosts[0]=coroot.dnor.io" \
      --set "corootCE.ingress.tls[0].secretName=coroot-tls" \
      --set "corootCE.ingress.annotations.cert-manager\.io/cluster-issuer=dnor-ca-issuer"

    echo -e "${BLUE}Deploying/Updating standalone ClickHouse...${NC}"
    
    # ClickHouse Users Config (Upsert)
    # OPTIMIZATION: Tuning for Low-Resource (1 Core) Environment
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
    # Note: We keep emptyDir for now as per previous successful fix for Longhorn issues
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

    echo -e "${BLUE}Configuring Coroot Connection...${NC}"
    
    # Ensure password env var is REMOVED (fix for upsert/clean state)
    # This prevents 'password authentication failed' if helm chart defaults drift
    kubectl set env deployment/coroot -n coroot BOOTSTRAP_CLICKHOUSE_PASSWORD- 2>/dev/null || true
    
    # Set the correct connection details
    kubectl set env deployment/coroot -n coroot \
      BOOTSTRAP_CLICKHOUSE_ADDRESS=clickhouse:9000 \
      BOOTSTRAP_CLICKHOUSE_USER=default \
      BOOTSTRAP_CLICKHOUSE_DATABASE=default

    echo -e "${BLUE}Waiting for pods to be ready...${NC}"
    kubectl wait --for=condition=ready pod -l app=clickhouse -n coroot --timeout=300s
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=coroot -n coroot --timeout=300s

    # 3. AUTOMATIC POSTGRES INTEGRATION
    echo -e "${BLUE}Scanning for Postgres deployments to enable Coroot Integration...${NC}"
    # Find deployments with "postgres" in name
    # Using jsonpath range to iterate
    PG_DEPLOYS=$(kubectl get deployments -A -o jsonpath='{range .items[?(@.metadata.name=="postgres-deployment")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}')
    
    if [ ! -z "$PG_DEPLOYS" ]; then
      while read -r NS NAME; do
        echo -e "${YELLOW}Found Postgres: $NAME in namespace $NS${NC}"
        # Try to find secret name from env vars
        SECRET_NAME=$(kubectl get deployment -n "$NS" "$NAME" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="POSTGRES_USER")].valueFrom.secretKeyRef.name}')
        
        if [ ! -z "$SECRET_NAME" ]; then
           echo -e "${GREEN}Found credentials secret: $SECRET_NAME. Configuring Coroot integration...${NC}"
           # Patch deployment with Coroot annotations
           kubectl patch deployment -n "$NS" "$NAME" --type='merge' -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"coroot.com/postgres-scrape\":\"true\",\"coroot.com/postgres-scrape-credentials-secret-name\":\"$SECRET_NAME\",\"coroot.com/postgres-scrape-credentials-secret-username-key\":\"POSTGRES_USER\",\"coroot.com/postgres-scrape-credentials-secret-password-key\":\"POSTGRES_PASSWORD\"}}}}}"
           echo -e "${GREEN}✓ patched deployment $NAME in $NS with Coroot annotations${NC}"
        else
           echo -e "${RED}Could not auto-detect secret for $NAME. Please annotate manually.${NC}"
        fi
      done <<< "$PG_DEPLOYS"
    else
      echo -e "${YELLOW}No specific 'postgres-deployment' found (searched for exact match).${NC}"
    fi

    # 2. OCI CLOUD PRICING (Automatic Fetch)
    echo -e "${BLUE}Detecting Cloud Environment & Pricing...${NC}"
    
    # Try to fetch OCI Metadata from Instance Metadata Service (IMDS)
    # Using curl inside the remote session; Fail fast (2s timeout) if not on OCI
    if OCI_META=$(curl -s --connect-timeout 2 --fail http://169.254.169.254/opc/v1/instance/ 2>/dev/null); then
       echo -e "${GREEN}✓ Successfully connected to OCI Metadata Service${NC}"
       
       # Check for A1 Flex Shape
       if echo "$OCI_META" | grep -q "VM.Standard.A1.Flex"; then
           SHAPE="VM.Standard.A1.Flex (ARM)"
           # OCI A1 Flex Pricing (Standard List Price)
           VCPU_PRICE="0.01"
           MEM_PRICE="0.0015"
           STORAGE_PRICE="0.0255"
           
           echo -e "${GREEN}✓ Identified Instance Shape: $SHAPE${NC}"
           echo -e "${GREEN}✓ Fetched Pricing Model: Oracle Cloud Infrastructure (Always Free Compatible)${NC}"
           
           echo -e "${YELLOW}ACTION REQUIRED: Configure these exact values in Coroot UI (Settings > Costs):${NC}"
           echo -e "  • vCPU Cost:   \$$VCPU_PRICE / hour"
           echo -e "  • Memory Cost: \$$MEM_PRICE / GB / hour"
           echo -e "  • Storage:     \$$STORAGE_PRICE / GB / month"
       else
           echo -e "${YELLOW}Detected OCI Environment but unknown shape. Please check OCI pricing calculator.${NC}"
           # Extract shape if possible
           RAW_SHAPE=$(echo "$OCI_META" | grep -o '"shape":\s*"[^"]*"' | cut -d'"' -f4)
           echo -e "Instance Shape: $RAW_SHAPE"
       fi
    else
       echo -e "${YELLOW}Could not fetch cloud metadata (Not OCI?). Using default pricing.${NC}"
    fi

    echo -e "${GREEN}Coroot Full Stack (Upserted) is Ready!${NC}"
EOF
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_coroot
fi
